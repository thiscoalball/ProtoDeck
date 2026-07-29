import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/network_configuration.dart';
import 'network_command_runner.dart';

class NetworkConfigurationInspector {
  NetworkConfigurationInspector({NetworkCommandRunner? runner})
    : _runner = runner ?? const NetworkCommandRunner();

  final NetworkCommandRunner _runner;

  Future<List<NetworkInterfaceConfiguration>> listInterfaces() async {
    if (Platform.isWindows) return _listWindowsInterfaces();
    if (Platform.isLinux) return _listLinuxInterfaces();
    return const [];
  }

  Future<NetworkInterfaceConfiguration?> inspect(String interfaceName) async {
    final values = await listInterfaces();
    return values
        .where((value) => value.interfaceName == interfaceName)
        .firstOrNull;
  }

  NetworkInterfaceConfiguration? resolveInterface(
    NetworkConfigurationTemplate template,
    List<NetworkInterfaceConfiguration> interfaces,
  ) {
    NetworkInterfaceConfiguration? named() => interfaces
        .where((value) => value.interfaceName == template.interfaceName)
        .firstOrNull;
    switch (template.interfaceMatchMode) {
      case NetworkInterfaceMatchMode.exactName:
        return named();
      case NetworkInterfaceMatchMode.macAddress:
        final target = _normalizeMac(template.interfaceMacAddress);
        return interfaces
                .where(
                  (value) =>
                      target.isNotEmpty &&
                      _normalizeMac(value.macAddress) == target,
                )
                .firstOrNull ??
            named();
      case NetworkInterfaceMatchMode.defaultTransport:
        final transport = template.interfaceTransport;
        return interfaces
                .where(
                  (value) =>
                      value.isDefault &&
                      (transport == null || value.transport == transport),
                )
                .firstOrNull ??
            interfaces
                .where(
                  (value) => transport != null && value.transport == transport,
                )
                .firstOrNull ??
            named();
    }
  }

  Future<NetworkConfigurationRestorePoint> captureRestorePoint(
    String interfaceName,
  ) async {
    final current = await inspect(interfaceName);
    if (current == null) {
      throw StateError('找不到网络接口 $interfaceName');
    }
    final raw = Platform.isLinux
        ? await _linuxRawProfile(interfaceName)
        : Platform.isWindows
        ? await _windowsRawProfile(interfaceName)
        : <String, Object?>{};
    return NetworkConfigurationRestorePoint(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      platform: Platform.operatingSystem,
      interfaceName: interfaceName,
      capturedAt: DateTime.now(),
      configuration: current,
      raw: raw,
    );
  }

  List<NetworkConfigurationDifference> differences(
    NetworkInterfaceConfiguration current,
    NetworkConfigurationTemplate desired,
  ) {
    final currentAddress = current.address == null
        ? '无'
        : '${current.address}/${current.prefixLength ?? 0}';
    final desiredAddress = desired.mode == NetworkAddressMode.dhcp
        ? '自动分配'
        : '${desired.address}/${desired.prefixLength}';
    final currentRoutes = current.routes.isEmpty
        ? '无'
        : current.routes
              .map(
                (value) =>
                    '${value.destination} via ${value.gateway} (${value.metric})',
              )
              .join(', ');
    final desiredRoutes = desired.staticRoutes.isEmpty
        ? '无'
        : desired.staticRoutes
              .map(
                (value) =>
                    '${value.destination} via ${value.gateway} (${value.metric})',
              )
              .join(', ');
    return [
      NetworkConfigurationDifference(
        label: '获取方式',
        before: current.mode == NetworkAddressMode.dhcp ? 'DHCP' : '静态',
        after: desired.mode == NetworkAddressMode.dhcp ? 'DHCP' : '静态',
      ),
      NetworkConfigurationDifference(
        label: 'IPv4',
        before: currentAddress,
        after: desiredAddress,
      ),
      NetworkConfigurationDifference(
        label: '默认网关',
        before: _shown(
          current.gateway,
          automatic: current.mode == NetworkAddressMode.dhcp,
        ),
        after: desired.mode == NetworkAddressMode.dhcp
            ? '自动'
            : _shown(desired.gateway),
      ),
      NetworkConfigurationDifference(
        label: 'DNS',
        before: current.dnsServers.isEmpty
            ? '自动/无'
            : current.dnsServers.join(', '),
        after:
            desired.mode == NetworkAddressMode.dhcp ||
                desired.dnsServers.isEmpty
            ? '自动'
            : desired.dnsServers.join(', '),
      ),
      NetworkConfigurationDifference(
        label: '接口 Metric',
        before: current.interfaceMetric?.toString() ?? '自动',
        after: desired.interfaceMetric?.toString() ?? '保持/自动',
      ),
      NetworkConfigurationDifference(
        label: '静态路由',
        before: currentRoutes,
        after: desiredRoutes,
      ),
    ];
  }

  Future<List<NetworkConfigurationVerificationItem>> verify(
    NetworkConfigurationTemplate desired,
  ) async {
    final current = await inspect(desired.interfaceName);
    if (current == null) {
      return const [
        NetworkConfigurationVerificationItem(
          label: '网络接口',
          expected: '存在',
          actual: '未找到',
          matches: false,
        ),
      ];
    }
    final values = <NetworkConfigurationVerificationItem>[
      NetworkConfigurationVerificationItem(
        label: 'DHCP 状态',
        expected: desired.mode == NetworkAddressMode.dhcp ? '已启用' : '已禁用',
        actual: current.mode == NetworkAddressMode.dhcp ? '已启用' : '已禁用',
        matches: current.mode == desired.mode,
      ),
    ];
    if (desired.mode == NetworkAddressMode.staticIpv4) {
      values.addAll([
        NetworkConfigurationVerificationItem(
          label: 'IPv4 地址',
          expected: desired.address ?? '无',
          actual: current.address ?? '无',
          matches: current.address == desired.address,
        ),
        NetworkConfigurationVerificationItem(
          label: '前缀长度',
          expected: '${desired.prefixLength}',
          actual: '${current.prefixLength ?? 0}',
          matches: current.prefixLength == desired.prefixLength,
        ),
        NetworkConfigurationVerificationItem(
          label: '默认网关',
          expected: desired.gateway ?? '无',
          actual: current.gateway ?? '无',
          matches: current.gateway == desired.gateway,
        ),
        NetworkConfigurationVerificationItem(
          label: 'DNS',
          expected: desired.dnsServers.isEmpty
              ? '自动'
              : desired.dnsServers.join(', '),
          actual: current.dnsServers.isEmpty
              ? '无'
              : current.dnsServers.join(', '),
          matches:
              desired.dnsServers.isEmpty ||
              _sameUnordered(current.dnsServers, desired.dnsServers),
        ),
      ]);
    } else {
      values.addAll([
        NetworkConfigurationVerificationItem(
          label: 'IPv4 地址与前缀',
          expected: '由 DHCP 自动获取',
          actual: current.address == null
              ? '尚未获取'
              : '${current.address}/${current.prefixLength ?? 0}',
          matches: current.address != null && current.prefixLength != null,
          requiredForWrite: false,
          detail: 'DHCP 地址可能在配置写入后延迟到达',
        ),
        NetworkConfigurationVerificationItem(
          label: '默认网关',
          expected: '由 DHCP 自动获取',
          actual: current.gateway ?? '尚未获取',
          matches: current.gateway?.isNotEmpty == true,
          requiredForWrite: false,
        ),
        NetworkConfigurationVerificationItem(
          label: 'DNS',
          expected: '由 DHCP 自动获取',
          actual: current.dnsServers.isEmpty
              ? '尚未获取'
              : current.dnsServers.join(', '),
          matches: current.dnsServers.isNotEmpty,
          requiredForWrite: false,
        ),
      ]);
    }
    if (desired.interfaceMetric != null) {
      values.add(
        NetworkConfigurationVerificationItem(
          label: '接口 Metric',
          expected: '${desired.interfaceMetric}',
          actual: '${current.interfaceMetric ?? '无'}',
          matches: current.interfaceMetric == desired.interfaceMetric,
        ),
      );
    }
    for (final route in desired.staticRoutes) {
      final actual = current.routes.where(
        (value) =>
            value.destination == route.destination &&
            value.gateway == route.gateway,
      );
      values.add(
        NetworkConfigurationVerificationItem(
          label: '静态路由 ${route.destination}',
          expected: '${route.gateway} · Metric ${route.metric}',
          actual: actual.isEmpty
              ? '未找到'
              : '${actual.first.gateway} · Metric ${actual.first.metric}',
          matches: actual.any((value) => value.metric == route.metric),
        ),
      );
    }
    values.add(
      NetworkConfigurationVerificationItem(
        label: '默认路由接口',
        expected: desired.interfaceName,
        actual: current.isDefault ? desired.interfaceName : '当前不是最优先默认路由',
        matches: desired.gateway == null || current.isDefault,
        detail: '多网卡环境中可能由其他接口的 Metric 决定',
        requiredForWrite: false,
      ),
    );
    if (Platform.isWindows) {
      values.add(
        NetworkConfigurationVerificationItem(
          label: 'Windows 网络 Profile',
          expected: '系统已识别',
          actual: [
            current.profileName,
            current.profileCategory,
          ].whereType<String>().where((value) => value.isNotEmpty).join(' · '),
          matches: current.profileName?.isNotEmpty == true,
          requiredForWrite: false,
        ),
      );
    }
    return values;
  }

  Future<IpConflictCheckResult> checkIpv4Conflict({
    required String interfaceName,
    required String address,
  }) async {
    final current = await inspect(interfaceName);
    if (current?.address == address) {
      return IpConflictCheckResult(
        state: IpConflictState.clear,
        address: address,
        message: '目标地址已由当前接口使用，不属于外部冲突',
      );
    }
    if (Platform.isLinux) {
      final result = await _runner.run('arping', [
        '-D',
        '-c',
        '2',
        '-w',
        '2',
        '-I',
        interfaceName,
        address,
      ], timeout: const Duration(seconds: 5));
      if (result.exitCode == 0) {
        return IpConflictCheckResult(
          state: IpConflictState.clear,
          address: address,
          message: '主动 ARP 重复地址探测未收到占用响应',
        );
      }
      if (result.exitCode == 1) {
        final neighbor = await _linuxNeighbor(interfaceName, address);
        return IpConflictCheckResult(
          state: IpConflictState.suspected,
          address: address,
          macAddress: neighbor,
          message: '主动 ARP 探测收到响应，目标地址可能已被占用',
        );
      }
      final neighbor = await _linuxNeighbor(interfaceName, address);
      return IpConflictCheckResult(
        state: neighbor == null
            ? IpConflictState.inconclusive
            : IpConflictState.suspected,
        address: address,
        macAddress: neighbor,
        message: neighbor == null
            ? '系统缺少 arping 或探测失败，无法确定地址是否空闲'
            : '邻居表中已存在该地址',
      );
    }
    if (Platform.isWindows)
      return _checkWindowsConflict(interfaceName, address);
    return IpConflictCheckResult(
      state: IpConflictState.inconclusive,
      address: address,
      message: '当前平台不支持主动 ARP 冲突检测',
    );
  }

  Future<NetworkConnectivityReport> runDiagnostics({
    required NetworkConfigurationTemplate template,
  }) async {
    final checks = <NetworkConnectivityCheck>[];
    final selected = template.diagnostics;
    final current = await inspect(template.interfaceName);
    if (selected.contains(NetworkDiagnosticKind.adapter)) {
      checks.add(
        NetworkConnectivityCheck(
          kind: NetworkDiagnosticKind.adapter,
          state: current?.connected == true
              ? NetworkCheckState.passed
              : NetworkCheckState.warning,
          title: '网卡链路',
          detail: current == null
              ? '未找到目标网卡'
              : current.connected
              ? '系统报告网卡已连接'
              : '网卡当前未连接，可稍后重新检测',
        ),
      );
    }
    final gateway = current?.gateway ?? template.gateway;
    if (selected.contains(NetworkDiagnosticKind.gateway)) {
      checks.add(
        gateway == null || gateway.isEmpty
            ? const NetworkConnectivityCheck(
                kind: NetworkDiagnosticKind.gateway,
                state: NetworkCheckState.notApplicable,
                title: '默认网关',
                detail: '当前配置没有默认网关',
              )
            : await _pingCheck(
                kind: NetworkDiagnosticKind.gateway,
                title: '默认网关',
                host: gateway,
              ),
      );
    }
    if (selected.contains(NetworkDiagnosticKind.dns)) {
      checks.add(await _dnsCheck());
    }
    if (selected.contains(NetworkDiagnosticKind.internet)) {
      checks.add(await _internetCheck());
    }
    return NetworkConnectivityReport(
      interfaceName: template.interfaceName,
      checkedAt: DateTime.now(),
      checks: checks,
    );
  }

  Future<List<NetworkInterfaceConfiguration>> _listWindowsInterfaces() async {
    final result = await _runner.run('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      _windowsInterfacesScript,
    ], timeout: const Duration(seconds: 18));
    if (result.exitCode != 0) {
      throw StateError('读取 Windows 网卡失败：${_firstLine(result)}');
    }
    final decoded = jsonDecode(result.stdout.trim());
    final rows = decoded is List ? decoded : [decoded];
    return rows
        .whereType<Map>()
        .map(
          (row) => NetworkInterfaceConfiguration.fromJson(
            row.map<String, Object?>((key, value) => MapEntry('$key', value)),
          ),
        )
        .where((value) => value.interfaceName.isNotEmpty)
        .toList(growable: false)
      ..sort(_interfaceSort);
  }

  Future<Map<String, Object?>> _windowsRawProfile(String interfaceName) async {
    final payload = base64Encode(utf8.encode(interfaceName));
    final script = _windowsSnapshotScript.replaceAll('__ALIAS__', payload);
    final result = await _runner.run('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ], timeout: const Duration(seconds: 12));
    if (result.exitCode != 0) {
      throw StateError('读取 Windows 配置快照失败：${_firstLine(result)}');
    }
    final decoded = jsonDecode(result.stdout.trim());
    if (decoded is! Map) throw StateError('Windows 配置快照格式无效');
    return decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
  }

  Future<List<NetworkInterfaceConfiguration>> _listLinuxInterfaces() async {
    final addressResult = await _runner.run('ip', const [
      '-j',
      'address',
      'show',
    ], timeout: const Duration(seconds: 8));
    final routeResult = await _runner.run('ip', const [
      '-4',
      '-j',
      'route',
      'show',
    ], timeout: const Duration(seconds: 8));
    if (addressResult.exitCode != 0) {
      throw StateError('读取 Linux 网卡失败：${_firstLine(addressResult)}');
    }
    final addresses = (jsonDecode(addressResult.stdout) as List<Object?>)
        .whereType<Map>()
        .toList(growable: false);
    final routes = routeResult.exitCode == 0
        ? (jsonDecode(routeResult.stdout) as List<Object?>)
              .whereType<Map>()
              .toList()
        : <Map>[];
    final defaultRoutes =
        routes.where((value) => value['dst'] == 'default').toList()
          ..sort((a, b) => _int(a['metric']).compareTo(_int(b['metric'])));
    final defaultName = defaultRoutes.firstOrNull?['dev']?.toString();
    final values = <NetworkInterfaceConfiguration>[];
    for (final row in addresses) {
      final name = row['ifname']?.toString() ?? '';
      if (name.isEmpty || name == 'lo') continue;
      final profile = await _linuxRawProfile(name);
      final addrRows = (row['addr_info'] as List<Object?>? ?? const [])
          .whereType<Map>();
      final ipv4 = addrRows
          .where(
            (value) => value['family'] == 'inet' && value['scope'] != 'host',
          )
          .firstOrNull;
      final interfaceRoutes = routes.where((value) => value['dev'] == name);
      final defaultRoute = interfaceRoutes
          .where((value) => value['dst'] == 'default')
          .firstOrNull;
      final customRoutes = <NetworkStaticRoute>[];
      for (final route in interfaceRoutes) {
        final destination = route['dst']?.toString();
        final gateway = route['gateway']?.toString();
        if (destination == null || destination == 'default' || gateway == null)
          continue;
        customRoutes.add(
          NetworkStaticRoute(
            destination: destination,
            gateway: gateway,
            metric: _int(route['metric'], fallback: 100),
          ),
        );
      }
      final dns = await _linuxDeviceValues(name, 'IP4.DNS');
      final connection = profile['connection']?.toString();
      values.add(
        NetworkInterfaceConfiguration(
          interfaceName: name,
          interfaceIndex: _int(row['ifindex']),
          description: connection == null || connection == '--'
              ? name
              : connection,
          status: row['operstate']?.toString() ?? 'unknown',
          transport: _linuxTransport(name),
          isDefault: name == defaultName,
          macAddress: row['address']?.toString(),
          linkSpeed: await _linuxSpeed(name),
          mode: profile['method'] == 'manual'
              ? NetworkAddressMode.staticIpv4
              : NetworkAddressMode.dhcp,
          address: ipv4?['local']?.toString(),
          prefixLength: _nullableInt(ipv4?['prefixlen']),
          gateway:
              defaultRoute?['gateway']?.toString() ??
              _nullable(profile['gateway']),
          dnsServers: dns.isEmpty
              ? _splitAddresses(profile['dns']?.toString())
              : dns,
          interfaceMetric: _nullableInt(
            defaultRoute?['metric'] ?? profile['routeMetric'],
          ),
          profileName: _nullable(connection),
          routes: customRoutes,
        ),
      );
    }
    values.sort(_interfaceSort);
    return values;
  }

  Future<Map<String, Object?>> _linuxRawProfile(String interfaceName) async {
    final connectionResult = await _runner.run('nmcli', [
      '-g',
      'GENERAL.CONNECTION',
      'device',
      'show',
      interfaceName,
    ], timeout: const Duration(seconds: 6));
    final connection = connectionResult.stdout
        .trim()
        .split(RegExp(r'\r?\n'))
        .firstOrNull;
    if (connectionResult.exitCode != 0 ||
        connection == null ||
        connection.isEmpty ||
        connection == '--') {
      return {'connection': connection ?? ''};
    }
    final result = await _runner.run('nmcli', [
      '-g',
      'ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns,ipv4.route-metric,ipv4.routes',
      'connection',
      'show',
      connection,
    ], timeout: const Duration(seconds: 8));
    final lines = result.stdout.split(RegExp(r'\r?\n'));
    return {
      'connection': connection,
      'method': lines.elementAtOrNull(0)?.trim() ?? 'auto',
      'addresses': lines.elementAtOrNull(1)?.trim() ?? '',
      'gateway': lines.elementAtOrNull(2)?.trim() ?? '',
      'dns': lines.elementAtOrNull(3)?.trim() ?? '',
      'ignoreAutoDns': lines.elementAtOrNull(4)?.trim() ?? 'no',
      'routeMetric': lines.elementAtOrNull(5)?.trim() ?? '',
      'routes': lines.skip(6).join('\n').trim(),
    };
  }

  Future<List<String>> _linuxDeviceValues(
    String interfaceName,
    String field,
  ) async {
    final result = await _runner.run('nmcli', [
      '-g',
      field,
      'device',
      'show',
      interfaceName,
    ], timeout: const Duration(seconds: 5));
    if (result.exitCode != 0) return const [];
    return result.stdout
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Future<String?> _linuxSpeed(String interfaceName) async {
    try {
      final value = (await File(
        '/sys/class/net/$interfaceName/speed',
      ).readAsString()).trim();
      final speed = int.tryParse(value);
      return speed == null || speed <= 0 ? null : '$speed Mbps';
    } on FileSystemException {
      return null;
    }
  }

  Future<String?> _linuxNeighbor(String interfaceName, String address) async {
    final result = await _runner.run('ip', [
      'neigh',
      'show',
      'to',
      address,
      'dev',
      interfaceName,
    ], timeout: const Duration(seconds: 4));
    final match = RegExp(
      r'lladdr\s+([0-9a-f:-]+)',
      caseSensitive: false,
    ).firstMatch(result.stdout);
    return match?.group(1)?.toUpperCase();
  }

  Future<IpConflictCheckResult> _checkWindowsConflict(
    String interfaceName,
    String address,
  ) async {
    final payload = base64Encode(
      utf8.encode(
        jsonEncode({'interfaceName': interfaceName, 'address': address}),
      ),
    );
    final script = _windowsConflictScript.replaceAll('__PAYLOAD__', payload);
    final result = await _runner.run('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ], timeout: const Duration(seconds: 8));
    if (result.exitCode != 0) {
      return IpConflictCheckResult(
        state: IpConflictState.inconclusive,
        address: address,
        message: '主动 ARP 探测失败：${_firstLine(result)}',
      );
    }
    try {
      final map = jsonDecode(result.stdout.trim()) as Map<String, Object?>;
      final occupied = map['occupied'] == true;
      return IpConflictCheckResult(
        state: occupied ? IpConflictState.suspected : IpConflictState.clear,
        address: address,
        macAddress: map['macAddress']?.toString(),
        message: occupied ? '主动 ARP 探测收到响应，目标地址可能已被占用' : '主动 ARP 探测未发现地址冲突',
      );
    } on Object {
      return IpConflictCheckResult(
        state: IpConflictState.inconclusive,
        address: address,
        message: '无法解析 Windows ARP 探测结果',
      );
    }
  }

  Future<NetworkConnectivityCheck> _pingCheck({
    required NetworkDiagnosticKind kind,
    required String title,
    required String host,
  }) async {
    final watch = Stopwatch()..start();
    final result = await _runner.run(
      Platform.isWindows ? 'ping.exe' : 'ping',
      Platform.isWindows
          ? ['-n', '1', '-w', '1500', host]
          : ['-c', '1', '-W', '2', host],
      timeout: const Duration(seconds: 4),
    );
    watch.stop();
    return NetworkConnectivityCheck(
      kind: kind,
      state: result.exitCode == 0
          ? NetworkCheckState.passed
          : NetworkCheckState.warning,
      title: title,
      detail: result.exitCode == 0 ? '$host 可达' : '$host 暂时无响应，上级设备可能尚未就绪',
      latencyMs: watch.elapsedMicroseconds / 1000,
    );
  }

  Future<NetworkConnectivityCheck> _dnsCheck() async {
    final watch = Stopwatch()..start();
    try {
      final values = await InternetAddress.lookup(
        'example.com',
      ).timeout(const Duration(seconds: 5));
      watch.stop();
      return NetworkConnectivityCheck(
        kind: NetworkDiagnosticKind.dns,
        state: values.isEmpty
            ? NetworkCheckState.warning
            : NetworkCheckState.passed,
        title: 'DNS 解析',
        detail: values.isEmpty ? '解析未返回地址' : '系统 DNS 解析可用',
        latencyMs: watch.elapsedMicroseconds / 1000,
      );
    } on Object catch (error) {
      watch.stop();
      return NetworkConnectivityCheck(
        kind: NetworkDiagnosticKind.dns,
        state: NetworkCheckState.warning,
        title: 'DNS 解析',
        detail: '暂时不可用：$error',
        latencyMs: watch.elapsedMicroseconds / 1000,
      );
    }
  }

  Future<NetworkConnectivityCheck> _internetCheck() async {
    final endpoints = <Uri>[
      Uri.parse('https://www.msftconnecttest.com/connecttest.txt'),
      Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
      Uri.parse('https://www.baidu.com/'),
    ];
    final watch = Stopwatch()..start();
    final attempts = await Future.wait(endpoints.map(_probeHttpEndpoint));
    watch.stop();
    final passed = attempts.where((value) => value).length;
    return NetworkConnectivityCheck(
      kind: NetworkDiagnosticKind.internet,
      state: passed > 0 ? NetworkCheckState.passed : NetworkCheckState.warning,
      title: '互联网访问',
      detail: passed > 0
          ? '$passed/${endpoints.length} 个外部端点可达'
          : '外部端点暂时不可达，不影响已写入的 IP 配置',
      latencyMs: watch.elapsedMicroseconds / 1000,
    );
  }

  Future<bool> _probeHttpEndpoint(Uri endpoint) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(endpoint)
          .timeout(const Duration(seconds: 5));
      request.followRedirects = true;
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 400;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static int _interfaceSort(
    NetworkInterfaceConfiguration a,
    NetworkInterfaceConfiguration b,
  ) {
    if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
    if (a.connected != b.connected) return a.connected ? -1 : 1;
    return a.interfaceName.compareTo(b.interfaceName);
  }

  static bool _sameUnordered(List<String> a, List<String> b) {
    final left = {...a.map((value) => value.trim().toLowerCase())};
    final right = {...b.map((value) => value.trim().toLowerCase())};
    return left.length == right.length && left.containsAll(right);
  }

  static String _shown(String? value, {bool automatic = false}) =>
      value == null || value.isEmpty ? (automatic ? '自动' : '无') : value;

  static String _normalizeMac(String? value) =>
      (value ?? '').replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();

  static String _linuxTransport(String name) {
    if (File('/sys/class/net/$name/wireless').existsSync()) return 'wifi';
    if (RegExp(r'^(wg|tun|tap|ppp)').hasMatch(name)) return 'vpn';
    if (RegExp(r'^(docker|veth|br-|virbr|vmnet|vbox)').hasMatch(name)) {
      return 'virtual';
    }
    return 'ethernet';
  }

  static List<String> _splitAddresses(String? value) => (value ?? '')
      .split(RegExp(r'[,;\s]+'))
      .map((item) => item.trim())
      .where((item) => InternetAddress.tryParse(item) != null)
      .toList(growable: false);

  static int _int(Object? value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
  static int? _nullableInt(Object? value) =>
      value == null || '$value'.isEmpty ? null : int.tryParse('$value');
  static String? _nullable(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == '--' ? null : text;
  }

  static String _firstLine(NetworkCommandResult result) =>
      '${result.stderr}\n${result.stdout}'
          .split(RegExp(r'\r?\n'))
          .map((value) => value.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '未知错误');

  static const _windowsInterfacesScript = r'''
$ErrorActionPreference = 'Stop'
$defaultRoute = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
$rows = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object { $_.Name -notmatch '^Loopback' } | ForEach-Object {
  $adapter = $_
  $index = [int]$adapter.InterfaceIndex
  $ipif = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
  $addresses = @(Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '127.*' -and $_.AddressState -ne 'Duplicate' })
  $address = $addresses | Where-Object { $_.AddressState -eq 'Preferred' } | Select-Object -First 1
  if (-not $address) { $address = $addresses | Select-Object -First 1 }
  $gatewayRoute = Get-NetRoute -InterfaceIndex $index -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
  $dns = @(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
  $profile = Get-NetConnectionProfile -InterfaceIndex $index -ErrorAction SilentlyContinue
  $label = "$($adapter.Name) $($adapter.InterfaceDescription)"
  $transport = 'ethernet'
  if ($label -match 'Wi-?Fi|Wireless|WLAN|802\.11') { $transport = 'wifi' }
  if ($label -match 'VPN|WireGuard|TAP|TUN|PPP') { $transport = 'vpn' }
  if ($label -match 'Hyper-V|Virtual|VMware|VirtualBox|Docker|WSL') { $transport = 'virtual' }
  $routes = @(Get-NetRoute -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -ne '0.0.0.0/0' -and $_.NextHop -ne '0.0.0.0' } | ForEach-Object { [pscustomobject]@{ destination="$($_.DestinationPrefix)"; gateway="$($_.NextHop)"; metric=[int]$_.RouteMetric } })
  [pscustomobject]@{
    interfaceName="$($adapter.Name)"
    interfaceIndex=$index
    description="$($adapter.InterfaceDescription)"
    status="$($adapter.Status)"
    transport=$transport
    isDefault=($defaultRoute -and [int]$defaultRoute.InterfaceIndex -eq $index)
    macAddress="$($adapter.MacAddress)"
    linkSpeed="$($adapter.LinkSpeed)"
    mode=if ($ipif -and "$($ipif.Dhcp)" -eq 'Enabled') { 'dhcp' } else { 'staticIpv4' }
    address=if ($address) { "$($address.IPAddress)" } else { $null }
    prefixLength=if ($address) { [int]$address.PrefixLength } else { $null }
    gateway=if ($gatewayRoute) { "$($gatewayRoute.NextHop)" } else { $null }
    dnsServers=$dns
    interfaceMetric=if ($ipif) { [int]$ipif.InterfaceMetric } else { $null }
    profileName=if ($profile) { "$($profile.Name)" } else { $null }
    profileCategory=if ($profile) { "$($profile.NetworkCategory)" } else { $null }
    routes=$routes
  }
})
$rows | ConvertTo-Json -Compress -Depth 6
''';

  static const _windowsConflictScript = r'''
$ErrorActionPreference = 'Stop'
$payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
$source = Get-NetIPAddress -InterfaceAlias ([string]$payload.interfaceName) -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.AddressState -eq 'Preferred' } | Select-Object -First 1 -ExpandProperty IPAddress
if (-not $source) { throw 'The selected interface has no IPv4 source address' }
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ProtoDeckArp {
  [DllImport("iphlpapi.dll", ExactSpelling=true)]
  public static extern int SendARP(uint destIp, uint srcIp, byte[] mac, ref uint length);
}
'@
function To-UInt32([string]$ip) {
  $bytes = [Net.IPAddress]::Parse($ip).GetAddressBytes()
  return [BitConverter]::ToUInt32($bytes, 0)
}
$mac = New-Object byte[] 6
$length = [uint32]$mac.Length
$code = [ProtoDeckArp]::SendARP((To-UInt32 ([string]$payload.address)), (To-UInt32 $source), $mac, [ref]$length)
$occupied = ($code -eq 0 -and $length -gt 0)
$shown = if ($occupied) { ($mac[0..($length-1)] | ForEach-Object { $_.ToString('X2') }) -join '-' } else { $null }
[pscustomobject]@{ occupied=$occupied; macAddress=$shown; code=$code } | ConvertTo-Json -Compress
''';

  static const _windowsSnapshotScript = r'''
$ErrorActionPreference = 'Stop'
$alias = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__ALIAS__'))
$ipif = Get-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction Stop | Select-Object -First 1
$addresses = @(Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '127.*' } | ForEach-Object { [pscustomobject]@{ address="$($_.IPAddress)"; prefix=[int]$_.PrefixLength } })
$defaultRoutes = @(Get-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ destination='0.0.0.0/0'; gateway="$($_.NextHop)"; metric=[int]$_.RouteMetric } })
$customRoutes = @(Get-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -ne '0.0.0.0/0' -and $_.NextHop -ne '0.0.0.0' } | ForEach-Object { [pscustomobject]@{ destination="$($_.DestinationPrefix)"; gateway="$($_.NextHop)"; metric=[int]$_.RouteMetric } })
$dns = @(Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
[pscustomobject]@{ dhcp=("$($ipif.Dhcp)" -eq 'Enabled'); interfaceMetric=[int]$ipif.InterfaceMetric; addresses=$addresses; defaultRoutes=$defaultRoutes; customRoutes=$customRoutes; dns=$dns } | ConvertTo-Json -Compress -Depth 5
''';
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

extension _ListElementAtOrNull<T> on List<T> {
  T? elementAtOrNull(int index) =>
      index >= 0 && index < length ? this[index] : null;
}
