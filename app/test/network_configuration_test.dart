import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/data/app_database.dart';
import 'package:nettools_mobile/models/network_configuration.dart';
import 'package:nettools_mobile/services/network_configuration_inspector.dart';
import 'package:nettools_mobile/services/network_configuration_service.dart';

void main() {
  NetworkConfigurationTemplate template({
    String id = 'office',
    String name = 'Office bench',
    NetworkAddressMode mode = NetworkAddressMode.staticIpv4,
  }) => NetworkConfigurationTemplate(
    id: id,
    name: name,
    interfaceName: 'Ethernet',
    mode: mode,
    address: mode == NetworkAddressMode.staticIpv4 ? '192.168.50.20' : null,
    prefixLength: 24,
    gateway: mode == NetworkAddressMode.staticIpv4 ? '192.168.50.1' : null,
    dnsServers: mode == NetworkAddressMode.staticIpv4
        ? const ['1.1.1.1', '8.8.8.8']
        : const [],
    updatedAt: DateTime.utc(2026, 7, 29),
  );

  test('static IPv4 template round-trips without losing DNS order', () {
    final original = template();
    original.validate();
    final decoded = decodeNetworkTemplates(encodeNetworkTemplates([original]));
    expect(decoded, hasLength(1));
    expect(decoded.single.address, '192.168.50.20');
    expect(decoded.single.prefixLength, 24);
    expect(decoded.single.dnsServers, ['1.1.1.1', '8.8.8.8']);
  });

  test('rejects invalid static address before any platform command runs', () {
    final invalid = NetworkConfigurationTemplate(
      id: 'bad',
      name: 'Invalid',
      interfaceName: 'eth0',
      mode: NetworkAddressMode.staticIpv4,
      address: '192.168.999.1',
      gateway: '192.168.1.1',
      updatedAt: DateTime.utc(2026),
    );
    expect(invalid.validate, throwsFormatException);
  });

  test('template repository updates by id and keeps newest first', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = NetworkConfigurationTemplateRepository(database);
    await repository.save(template(id: 'office', name: 'Old office'));
    await repository.save(
      NetworkConfigurationTemplate(
        id: 'home',
        name: 'Home DHCP',
        interfaceName: 'Wi-Fi',
        mode: NetworkAddressMode.dhcp,
        updatedAt: DateTime.utc(2026, 7, 30),
      ),
    );
    await repository.save(template(id: 'office', name: 'Office updated'));

    final rows = await repository.load();
    expect(rows, hasLength(2));
    expect(rows.first.name, 'Home DHCP');
    expect(rows.last.name, 'Office updated');
  });

  test('malformed persisted template payload is ignored safely', () {
    expect(decodeNetworkTemplates('{not json'), isEmpty);
    expect(decodeNetworkTemplates('{"value": 1}'), isEmpty);
  });

  test('advanced template fields survive export and import', () {
    final original = NetworkConfigurationTemplate(
      id: 'advanced',
      name: 'Lab static',
      interfaceName: 'Ethernet 2',
      interfaceMatchMode: NetworkInterfaceMatchMode.macAddress,
      interfaceMacAddress: '00:11:22:33:44:55',
      interfaceTransport: 'ethernet',
      mode: NetworkAddressMode.staticIpv4,
      address: '10.20.30.40',
      prefixLength: 24,
      dnsServers: const ['223.5.5.5'],
      interfaceMetric: 25,
      staticRoutes: const [
        NetworkStaticRoute(
          destination: '172.16.0.0/12',
          gateway: '10.20.30.1',
          metric: 50,
        ),
      ],
      diagnostics: const {
        NetworkDiagnosticKind.adapter,
        NetworkDiagnosticKind.dns,
      },
      updatedAt: DateTime.utc(2026, 7, 29),
    );

    final decoded = decodeNetworkTemplates(encodeNetworkTemplates([original]));
    final restored = decoded.single;
    expect(restored.interfaceMatchMode, NetworkInterfaceMatchMode.macAddress);
    expect(restored.interfaceMacAddress, '00:11:22:33:44:55');
    expect(restored.interfaceMetric, 25);
    expect(restored.staticRoutes.single.destination, '172.16.0.0/12');
    expect(restored.staticRoutes.single.metric, 50);
    expect(restored.diagnostics, {
      NetworkDiagnosticKind.adapter,
      NetworkDiagnosticKind.dns,
    });
  });

  test('last configuration restore point round-trips independently', () {
    final point = NetworkConfigurationRestorePoint(
      id: 'before-change',
      platform: 'linux',
      interfaceName: 'enp1s0',
      capturedAt: DateTime.utc(2026, 7, 29, 10, 30),
      configuration: const NetworkInterfaceConfiguration(
        interfaceName: 'enp1s0',
        description: 'Wired adapter',
        status: 'connected',
        transport: 'ethernet',
        isDefault: true,
        mode: NetworkAddressMode.dhcp,
        address: '192.168.8.112',
        prefixLength: 24,
        gateway: '192.168.8.1',
        dnsServers: ['192.168.8.1'],
        interfaceMetric: 100,
      ),
      raw: const {'profile': 'Wired connection 1', 'method': 'auto'},
    );

    final restored = decodeNetworkRestorePoint(
      encodeNetworkRestorePoint(point),
    );
    expect(restored, isNotNull);
    expect(restored!.interfaceName, 'enp1s0');
    expect(restored.configuration.gateway, '192.168.8.1');
    expect(restored.raw['method'], 'auto');
  });

  test('configuration preview identifies changed and unchanged fields', () {
    const current = NetworkInterfaceConfiguration(
      interfaceName: 'Ethernet',
      description: 'Adapter',
      status: 'up',
      transport: 'ethernet',
      isDefault: true,
      mode: NetworkAddressMode.dhcp,
      address: '192.168.8.112',
      prefixLength: 24,
      gateway: '192.168.8.1',
      dnsServers: ['192.168.8.1'],
      interfaceMetric: 25,
    );
    final desired = template().copyWith(
      interfaceName: 'Ethernet',
      address: '192.168.8.20',
      gateway: '192.168.8.1',
      dnsServers: const ['223.5.5.5', '1.1.1.1'],
      interfaceMetric: 25,
    );

    final differences = NetworkConfigurationInspector().differences(
      current,
      desired,
    );
    expect(differences, hasLength(6));
    expect(
      differences.where((value) => value.changed).map((value) => value.label),
      containsAll(['获取方式', 'IPv4', 'DNS']),
    );
    expect(
      differences.singleWhere((value) => value.label == '接口 Metric').changed,
      isFalse,
    );
  });

  test('static configuration allows an empty gateway for isolated LANs', () {
    final isolated = template().copyWith(gateway: '');
    expect(isolated.validate, returnsNormally);
  });
}
