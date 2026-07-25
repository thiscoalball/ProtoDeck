import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/stun_service.dart';

void main() {
  test('parses a real RFC 5389 XOR-MAPPED-ADDRESS response', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final handled = Completer<void>();
    final subscription = server.listen((event) {
      if (event != RawSocketEvent.read) return;
      final request = server.receive();
      if (request == null || request.data.length < 20) return;
      final response = Uint8List(32);
      final data = ByteData.sublistView(response);
      data.setUint16(0, 0x0101);
      data.setUint16(2, 12);
      data.setUint32(4, 0x2112A442);
      response.setRange(8, 20, request.data.sublist(8, 20));
      data.setUint16(20, 0x0020);
      data.setUint16(22, 8);
      response[25] = 0x01;
      data.setUint16(26, 45678 ^ 0x2112);
      final mapped = InternetAddress('203.0.113.9').rawAddress;
      const cookie = [0x21, 0x12, 0xA4, 0x42];
      for (var i = 0; i < 4; i++) response[28 + i] = mapped[i] ^ cookie[i];
      server.send(response, request.address, request.port);
      if (!handled.isCompleted) handled.complete();
    });
    try {
      final result = await StunService().binding(
        server: '127.0.0.1',
        port: server.port,
        timeout: const Duration(seconds: 2),
      );
      expect(result.mappedAddress, '203.0.113.9');
      expect(result.mappedPort, 45678);
      await handled.future;
    } finally {
      await subscription.cancel();
      server.close();
    }
  });
}
