import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/local_discovery_service.dart';

void main() {
  final service = LocalDiscoveryService();

  test('rejects SSDP header injection before opening a socket', () async {
    await expectLater(
      service.discoverSsdp(searchTarget: 'ssdp:all\r\nX-Test: injected'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects invalid mDNS labels before opening a socket', () async {
    await expectLater(
      service.discoverMdns(queryName: '${List.filled(64, 'a').join()}.local'),
      throwsA(isA<FormatException>()),
    );
  });
}
