import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/port_scan_service.dart';

void main() {
  final service = PortScanService();

  test('parses individual ports and ranges', () {
    expect(service.parsePorts('443,80,8000-8002'), [80, 443, 8000, 8001, 8002]);
  });

  test('rejects invalid and excessive ranges', () {
    expect(() => service.parsePorts('0'), throwsFormatException);
    expect(() => service.parsePorts('1-300'), throwsFormatException);
    expect(() => service.parsePorts('abc'), throwsFormatException);
  });

  test('classifies an open port and captures a bounded banner', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((socket) {
      socket.write('SSH-2.0-ProtoDeck_Test\r\n');
      socket.flush();
    });
    final results = await service
        .scan(
          host: '127.0.0.1',
          ports: [server.port],
          timeout: const Duration(seconds: 1),
          token: CancellationToken(),
          grabBanner: true,
          concurrency: 1,
          addressType: InternetAddressType.IPv4,
        )
        .toList();

    expect(results.single.state, PortState.open);
    expect(results.single.address, '127.0.0.1');
    expect(results.single.banner, startsWith('SSH-2.0'));
    await subscription.cancel();
    await server.close();
  });
}
