import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/dns_service.dart';

void main() {
  test('performs and parses a real UDP DNS exchange', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final handled = Completer<void>();
    late StreamSubscription<RawSocketEvent> subscription;
    subscription = server.listen((event) {
      if (event != RawSocketEvent.read) return;
      final request = server.receive();
      if (request == null) return;
      final query = request.data;
      final response = <int>[
        query[0],
        query[1],
        0x81,
        0x80,
        0x00,
        0x01,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        ...query.sublist(12),
        0xc0,
        0x0c,
        0x00,
        0x01,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x3c,
        0x00,
        0x04,
        1,
        2,
        3,
        4,
      ];
      server.send(response, request.address, request.port);
      if (!handled.isCompleted) handled.complete();
    });
    addTearDown(() async {
      await subscription.cancel();
      server.close();
    });

    final result = await DnsService().lookup(
      'example.com',
      server: '127.0.0.1',
      port: server.port,
    );
    await handled.future;

    expect(result.success, isTrue, reason: result.error);
    expect(result.rcode, 'NOERROR');
    expect(result.records, hasLength(1));
    expect(result.records.single.type, 'A');
    expect(result.records.single.data, '1.2.3.4');
    expect(result.records.single.ttl, 60);
  });

  test('parses TLSA and HTTPS service-binding records', () async {
    final server = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    late StreamSubscription<RawSocketEvent> subscription;
    subscription = server.listen((event) {
      if (event != RawSocketEvent.read) return;
      final request = server.receive();
      if (request == null) return;
      final query = request.data;
      final type = (query[query.length - 4] << 8) | query[query.length - 3];
      final rdata = type == 52
          ? <int>[3, 1, 1, 0xAA, 0xBB, 0xCC]
          : <int>[
              0,
              1,
              0,
              0,
              1,
              0,
              6,
              2,
              0x68,
              0x32,
              2,
              0x68,
              0x33,
              0,
              3,
              0,
              2,
              1,
              0xBB,
            ];
      final response = <int>[
        query[0],
        query[1],
        0x81,
        0x80,
        0,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        ...query.sublist(12),
        0xc0,
        0x0c,
        type >> 8,
        type & 0xff,
        0,
        1,
        0,
        0,
        0,
        60,
        rdata.length >> 8,
        rdata.length & 0xff,
        ...rdata,
      ];
      server.send(response, request.address, request.port);
    });
    addTearDown(() async {
      await subscription.cancel();
      server.close();
    });

    final tlsa = await DnsService().lookup(
      '_443._tcp.example.com',
      type: DnsRecordType.tlsa,
      server: '127.0.0.1',
      port: server.port,
    );
    expect(tlsa.records.single.data, contains('usage=3'));
    expect(tlsa.records.single.data, contains('certificateAssociation=AABBCC'));

    final https = await DnsService().lookup(
      'example.com',
      type: DnsRecordType.https,
      server: '127.0.0.1',
      port: server.port,
    );
    expect(https.records.single.data, contains('priority=1'));
    expect(https.records.single.data, contains('alpn=h2,h3'));
    expect(https.records.single.data, contains('port=443'));
  });
}
