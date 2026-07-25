import '../models/network_context.dart';
import 'native_network_service.dart';
import 'public_ip_service.dart';

class NetworkContextService {
  NetworkContextService({
    NativeNetworkService? native,
    PublicIpService? publicIp,
  }) : _native = native ?? NativeNetworkService(),
       _publicIp = publicIp ?? PublicIpService();

  final NativeNetworkService _native;
  final PublicIpService _publicIp;

  Future<NetworkContext> load({bool includePublicAddresses = true}) async {
    final context = await _native.getNetworkContext();
    if (!context.connected || !includePublicAddresses) return context;
    final results = await Future.wait([_publicIp.ipv4(), _publicIp.ipv6()]);
    return context.copyWith(publicIpv4: results[0], publicIpv6: results[1]);
  }

  void close() => _publicIp.close();
}
