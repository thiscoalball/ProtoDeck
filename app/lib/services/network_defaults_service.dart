import 'ip_tools_service.dart';
import 'native_network_service.dart';

class NetworkDefaults {
  const NetworkDefaults({this.gateway, this.subnet});
  final String? gateway;
  final String? subnet;
}

class NetworkDefaultsService {
  Future<NetworkDefaults> load() async {
    try {
      final context = await NativeNetworkService().getNetworkContext();
      final gateways = [...context.lanGateways, ...context.gateways];
      String? gateway;
      for (final candidate in gateways) {
        final classification = IpToolsService().classify(candidate);
        if (classification.version == 4 && !classification.isPublic) {
          gateway = candidate;
          break;
        }
      }
      final addresses = [...context.lanAddresses, ...context.addresses];
      for (final address in addresses) {
        if (address.family != 'IPv4') continue;
        final classification = IpToolsService().classify(address.address);
        if (classification.isPublic) continue;
        final prefix = address.prefixLength < 20 ? 24 : address.prefixLength;
        final value = IpToolsService().parseIpv4(address.address);
        final mask = prefix == 0
            ? 0
            : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
        return NetworkDefaults(
          gateway: gateway,
          subnet: '${IpToolsService().formatIpv4(value & mask)}/$prefix',
        );
      }
      if (gateway != null) {
        final value = IpToolsService().parseIpv4(gateway);
        return NetworkDefaults(
          gateway: gateway,
          subnet: '${IpToolsService().formatIpv4(value & 0xFFFFFF00)}/24',
        );
      }
    } on Object {
      // Defaults are optional on non-Android platforms and disconnected devices.
    }
    return const NetworkDefaults();
  }
}
