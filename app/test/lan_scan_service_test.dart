import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/lan_scan_service.dart';

void main() {
  test('LAN scan completes and reports progress without hanging', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    final progress = await LanScanService()
        .scan(
          '127.0.0.1/32',
          ports: [server.port],
          concurrency: 1,
          timeout: const Duration(milliseconds: 300),
        )
        .toList()
        .timeout(const Duration(seconds: 3));

    expect(progress.last.running, isFalse);
    expect(progress.last.completed, 1);
    expect(progress.last.devices.single.address, '127.0.0.1');
    expect(progress.last.devices.single.openPorts, contains(server.port));
  });
}
