import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/wake_on_lan_service.dart';

void main() {
  test('sends a correctly encoded 102-byte magic packet', () async {
    final listener = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final packet = Completer<List<int>>();
    final subscription = listener.listen((event) {
      if (event != RawSocketEvent.read || packet.isCompleted) return;
      final datagram = listener.receive();
      if (datagram != null) packet.complete(datagram.data);
    });
    try {
      final sent = await WakeOnLanService().send(
        mac: 'AA:BB:CC:DD:EE:FF',
        broadcast: '127.0.0.1',
        port: listener.port,
        repeat: 1,
      );
      final bytes = await packet.future.timeout(const Duration(seconds: 2));
      expect(sent, 1);
      expect(bytes.length, 102);
      expect(bytes.take(6), everyElement(0xff));
      expect(bytes.sublist(6, 12), [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]);
      expect(bytes.sublist(96, 102), [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]);
    } finally {
      await subscription.cancel();
      listener.close();
    }
  });

  test('rejects malformed MAC addresses before sending', () async {
    expect(
      () => WakeOnLanService().send(mac: 'not-a-mac'),
      throwsA(isA<FormatException>()),
    );
  });
}
