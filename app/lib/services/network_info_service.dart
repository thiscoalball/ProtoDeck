import 'dart:io';

class NetworkInterfaceInfo {
  const NetworkInterfaceInfo({required this.name, required this.addresses});

  final String name;
  final List<InternetAddress> addresses;
}

class NetworkInfoSnapshot {
  const NetworkInfoSnapshot({required this.interfaces, required this.hostname});

  final List<NetworkInterfaceInfo> interfaces;
  final String hostname;

  bool get hasNetwork => interfaces.any((item) => item.addresses.isNotEmpty);

  Iterable<InternetAddress> get allAddresses =>
      interfaces.expand((item) => item.addresses);
}

class NetworkInfoService {
  Future<NetworkInfoSnapshot> load() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: true,
      type: InternetAddressType.any,
    );
    return NetworkInfoSnapshot(
      hostname: Platform.localHostname,
      interfaces: interfaces
          .map(
            (item) => NetworkInterfaceInfo(
              name: item.name,
              addresses: List.unmodifiable(item.addresses),
            ),
          )
          .toList(growable: false),
    );
  }
}
