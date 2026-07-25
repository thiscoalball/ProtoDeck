import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/local_test_server_service.dart';

void main() {
  final service = LocalTestServerService.instance;

  tearDown(() async {
    await service.stop();
    service.clearEvents();
  });

  test('HTTP server responds and records safe request details', () async {
    await service.start(
      mode: LocalTestServerMode.http,
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4.address,
      httpResponseBody: '{"service":"ready"}',
      httpContentType: 'application/json; charset=utf-8',
      httpStatusCode: HttpStatus.accepted,
      httpHeaders: const {'x-test-node': 'phone'},
    );
    expect(service.snapshot.running, isTrue);
    expect(service.snapshot.port, greaterThan(0));

    final eventFuture = service.changes
        .expand((snapshot) => snapshot.events)
        .firstWhere((event) => event.kind == 'HTTP');
    final client = HttpClient();
    final request = await client.post(
      InternetAddress.loopbackIPv4.address,
      service.snapshot.port,
      '/service/check?token=visible',
    );
    request.headers.set('x-forwarded-for', '203.0.113.8');
    request.headers.set('x-forwarded-proto', 'https');
    request.headers.set('authorization', 'Bearer must-not-be-logged');
    request.headers.set('cookie', 'secret=value');
    request.write('{"ping":true}');
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    final event = await eventFuture.timeout(const Duration(seconds: 3));

    expect(response.statusCode, HttpStatus.accepted);
    expect(response.headers.value('x-local-test-server'), 'active');
    expect(response.headers.value('x-test-node'), 'phone');
    expect(body, '{"service":"ready"}');
    expect(
      event.summary,
      contains('POST /service/check?token=<redacted> · 202'),
    );
    expect(event.detail, contains('x-forwarded-for: 203.0.113.8'));
    expect(event.detail, contains('x-forwarded-proto: https'));
    expect(event.detail, contains('body-size: 13 B'));
    expect(event.detail, isNot(contains('must-not-be-logged')));
    expect(event.detail, isNot(contains('secret=value')));
    expect(service.snapshot.requestCount, 1);
    expect(service.snapshot.receivedBytes, greaterThan(0));
    expect(service.snapshot.sentBytes, utf8.encode(body).length);
    client.close(force: true);
  });

  test(
    'HTTP server rejects unsafe manually managed response headers',
    () async {
      await expectLater(
        service.start(
          mode: LocalTestServerMode.http,
          port: 0,
          bindAddress: InternetAddress.loopbackIPv4.address,
          httpHeaders: const {'Content-Length': '12'},
        ),
        throwsA(isA<FormatException>()),
      );
      expect(service.snapshot.running, isFalse);
    },
  );

  test('TCP echo supports a clean stop and restart', () async {
    await service.start(
      mode: LocalTestServerMode.tcpEcho,
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4.address,
    );
    final firstPort = service.snapshot.port;
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      firstPort,
    );
    final replyFuture = socket.first;
    socket.add(utf8.encode('echo-check'));
    await socket.flush();
    final reply = await replyFuture.timeout(const Duration(seconds: 3));
    expect(utf8.decode(reply), 'echo-check');
    expect(service.snapshot.connectionCount, 1);
    expect(service.snapshot.receivedBytes, 10);
    expect(service.snapshot.sentBytes, 10);
    socket.destroy();

    await service.stop();
    expect(service.snapshot.status, LocalTestServerStatus.stopped);
    await expectLater(
      Socket.connect(
        InternetAddress.loopbackIPv4,
        firstPort,
        timeout: const Duration(milliseconds: 400),
      ),
      throwsA(isA<SocketException>()),
    );

    await service.start(
      mode: LocalTestServerMode.tcpEcho,
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4.address,
    );
    expect(service.snapshot.running, isTrue);
    expect(service.snapshot.port, greaterThan(0));
  });
}
