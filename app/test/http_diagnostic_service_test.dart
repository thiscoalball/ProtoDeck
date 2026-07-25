import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/http_diagnostic_service.dart';

void main() {
  test(
    'HTTP diagnostics retain redirects, endpoints, timings and metadata',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        if (request.uri.path == '/redirect') {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '/final');
        } else {
          request.response
            ..headers.contentType = ContentType.json
            ..headers.set('x-content-type-options', 'nosniff')
            ..write(jsonEncode({'ok': true}));
        }
        await request.response.close();
      });

      try {
        final result = await HttpDiagnosticService().request(
          uri: Uri.parse(
            'http://${InternetAddress.loopbackIPv4.address}:${server.port}/redirect',
          ),
        );
        expect(result.statusCode, HttpStatus.ok);
        expect(result.redirects, isNotEmpty);
        expect(result.remoteAddress, InternetAddress.loopbackIPv4.address);
        expect(result.localAddress, isNotEmpty);
        expect(result.localPort, greaterThan(0));
        expect(result.remotePort, server.port);
        expect(result.contentType, 'application/json');
        expect(result.body, contains('"ok":true'));
        expect(result.totalTime, greaterThanOrEqualTo(result.timeToFirstByte));
        expect(result.preTransferTime, greaterThanOrEqualTo(Duration.zero));
        expect(
          result.securityObservations,
          contains(HttpSecurityObservation.plainHttp),
        );
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    },
  );

  test('HTTP diagnostics enforce the retained body limit', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.write('0123456789');
      await request.response.close();
    });
    try {
      final result = await HttpDiagnosticService().request(
        uri: Uri.parse(
          'http://${InternetAddress.loopbackIPv4.address}:${server.port}/',
        ),
        maxBodyBytes: 4,
      );
      expect(result.body, '0123');
      expect(result.receivedBytes, 10);
      expect(result.bodyTruncated, isTrue);
    } finally {
      await server.close(force: true);
      await subscription.cancel();
    }
  });
}
