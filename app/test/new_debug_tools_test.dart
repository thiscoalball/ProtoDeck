import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/api_workbench_service.dart';
import 'package:nettools_mobile/services/developer_tools_service.dart';
import 'package:nettools_mobile/services/socket_debug_service.dart';

void main() {
  test('generator emits valid UUID v7 and bounded random tokens', () {
    final service = DeveloperToolsService();
    final uuid = service.generate('uuid7');
    expect(
      uuid,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(service.generate('hex', length: 16), hasLength(32));
    expect(service.generate('base64url', length: 12), hasLength(16));
  });
  test('imports cURL without invoking a shell', () {
    final request = ApiWorkbenchService.parseCurl(
      "curl -X POST 'https://example.test/items' "
      "-H 'Content-Type: application/json' "
      "-H 'X-Trace: abc' --data-raw '{\"ok\":true}'",
    );
    expect(request.method, 'POST');
    expect(request.url, 'https://example.test/items');
    expect(request.headers['Content-Type'], 'application/json');
    expect(request.headers['X-Trace'], 'abc');
    expect(request.body, '{"ok":true}');
  });

  group('socket payload', () {
    test('parses separated hex bytes', () {
      expect(
        SocketDebugService.parsePayload('48 65-6c:6C 6f', hex: true),
        utf8.encode('Hello'),
      );
    });

    test('rejects incomplete byte', () {
      expect(
        () => SocketDebugService.parsePayload('ABC', hex: true),
        throwsFormatException,
      );
    });
  });

  group('API workbench helpers', () {
    test('parses headers and substitutes variables', () {
      final value = ApiWorkbenchService.substitute(
        'Bearer {{token}} @ {{base}}',
        {'token': 'abc', 'base': 'example.com'},
      );
      expect(value, 'Bearer abc @ example.com');
      expect(
        ApiWorkbenchService.parseHeaders('Accept: application/json\nX-ID: 42'),
        {'Accept': 'application/json', 'X-ID': '42'},
      );
    });

    test('exports cURL with safe single quote escaping', () {
      final value = ApiWorkbenchService.curl(
        method: 'POST',
        url: 'https://example.com',
        headers: {'X-Test': "a'b"},
        body: '{"ok":true}',
      );
      expect(value, contains("curl -X POST 'https://example.com'"));
      expect(value, contains('--data-raw'));
    });

    test('SSE parser groups fields into structured events', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'event: delta\nid: 7\ndata: {"content":\ndata: "你好"}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      final session = SseDebugSession();
      final received = session.messages
          .where((message) => message.direction == 'RX')
          .take(2)
          .toList();
      await session.connect(
        'http://${server.address.address}:${server.port}/events',
      );
      final events = await received.timeout(const Duration(seconds: 3));
      expect(events, hasLength(2));
      expect(events.first.channel, 'delta');
      expect(events.first.metadata['id'], '7');
      expect(jsonDecode(events.first.data), {'content': '你好'});
      expect(events.last.data, '[DONE]');
      await session.dispose();
      await server.close(force: true);
    });

    test('WebSocket preserves JSON messages as structured records', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen(socket.add);
      });
      final session = WebSocketDebugSession();
      final received = session.messages.firstWhere(
        (message) => message.direction == 'RX',
      );
      await session.connect(
        'ws://${server.address.address}:${server.port}/socket',
      );
      session.send('{"ok":true}');
      final message = await received.timeout(const Duration(seconds: 3));
      expect(message.kind, 'json');
      expect(message.prettyData, contains('"ok": true'));
      expect(message.size, greaterThan(0));
      await session.dispose();
      await server.close(force: true);
    });

    test('MQTT parser keeps topic, JSON and QoS metadata', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((client) {
        var sent = false;
        client.listen((_) {
          if (sent) return;
          sent = true;
          final topic = utf8.encode('nettools/test');
          final payload = utf8.encode('{"value":42}');
          final remaining = 2 + topic.length + payload.length;
          client.add([
            0x20,
            0x02,
            0x00,
            0x00,
            0x30,
            remaining,
            0,
            topic.length,
            ...topic,
            ...payload,
          ]);
        }, onError: (_) {});
      });
      final session = MqttDebugSession();
      final received = session.messages.firstWhere(
        (message) => message.direction == 'RX',
      );
      await session.connect(
        host: server.address.address,
        port: server.port,
        clientId: 'test-client',
      );
      final message = await received.timeout(const Duration(seconds: 3));
      expect(message.channel, 'nettools/test');
      expect(message.kind, 'json');
      expect(message.metadata['qos'], 0);
      expect(jsonDecode(message.data), {'value': 42});
      await session.dispose();
      await server.close();
    });
  });

  group('advanced developer tools', () {
    final tools = DeveloperToolsService();

    test('hash and HMAC are deterministic', () {
      expect(
        tools.digestText('abc', 'sha256'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(tools.digestText('abc', 'sha256', key: 'key'), hasLength(64));
      final all = tools.digestAll('abc');
      expect(
        all.keys,
        containsAll(['MD5', 'SHA-1', 'SHA-256', 'SHA-512', 'CRC32']),
      );
      expect(all['SHA-256'], tools.digestText('abc', 'sha256'));
    });

    test('JWT decoder exposes claims', () {
      final token = [
        base64Url.encode(utf8.encode('{"alg":"none"}')).replaceAll('=', ''),
        base64Url
            .encode(utf8.encode('{"sub":"42","exp":2000000000}'))
            .replaceAll('=', ''),
        'signature',
      ].join('.');
      final output = tools.decodeJwt(token);
      expect(output, contains('"sub": "42"'));
      expect(output, contains('exp:'));
    });

    test(
      'JWT decoder verifies HMAC signatures without persisting a secret',
      () {
        final header = base64Url
            .encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'))
            .replaceAll('=', '');
        final payload = base64Url
            .encode(utf8.encode('{"sub":"42","exp":4102444800}'))
            .replaceAll('=', '');
        final input = '$header.$payload';
        final signature = base64Url
            .encode(
              Hmac(
                sha256,
                utf8.encode('secret'),
              ).convert(utf8.encode(input)).bytes,
            )
            .replaceAll('=', '');
        final token = '$input.$signature';

        expect(
          tools.decodeJwt(token, secret: 'secret'),
          contains('Signature status: VALID'),
        );
        expect(
          tools.decodeJwt(token, secret: 'wrong'),
          contains('Signature status: INVALID'),
        );
      },
    );

    test('chmod converts both directions', () {
      expect(tools.chmodConvert('755'), contains('rwxr-xr-x'));
      expect(tools.chmodConvert('rw-r-----'), contains('640'));
      expect(tools.chmodConvert('4755'), contains('rwsr-xr-x'));
      expect(tools.chmodConvert('rwsr-xr-x'), contains('4755'));
      expect(tools.chmodConvert('1777'), contains('rwxrwxrwt'));
    });

    test('Unicode conversion preserves supplementary characters', () {
      final encoded = tools.unicodeConvert('ProtoDeck 😀');
      expect(encoded, contains(r'\ud83d\ude00'));
      expect(tools.unicodeConvert(encoded, decode: true), 'ProtoDeck 😀');
      expect(tools.unicodeConvert(r'\u{1F600}', decode: true), '😀');
    });

    test('bit calculator exposes rotations, signed value and byte order', () {
      final rotated = tools.bitCalculate(
        left: '0x81',
        operation: 'ROL',
        right: '1',
        width: 8,
      );
      expect(rotated['十六进制'], '0x03');
      expect(rotated['有符号十进制（补码）'], '3');
      final signed = tools.bitCalculate(
        left: '0xFF80',
        operation: 'OR',
        right: '0',
        width: 16,
      );
      expect(signed['有符号十进制（补码）'], '-128');
      expect(signed['小端字节'], '80 FF');
    });

    test('gzip round trip', () {
      final encoded = tools.compression('NetTools 中文');
      final payload = encoded.split('\n\n').last;
      expect(tools.compression(payload, decode: true), 'NetTools 中文');
      expect(encoded, contains('CRC32:'));
      expect(encoded, contains('Base64 长度:'));
    });

    test('HTML entities support named and supplementary code points', () {
      expect(
        tools.htmlEntityConvert('&copy; &euro; &#x1F600;', decode: true),
        '© € 😀',
      );
      expect(
        () => tools.htmlEntityConvert('&#xD800;', decode: true),
        throwsFormatException,
      );
    });

    test('CRC32 and structured conversions', () {
      expect(tools.digestText('123456789', 'crc32'), 'cbf43926');
      expect(
        tools.convertStructuredData('name,age\nAlice,30', 'csv_json'),
        contains('"Alice"'),
      );
      expect(
        tools.convertStructuredData('[{"name":"Alice","age":30}]', 'json_csv'),
        contains('Alice'),
      );
    });

    test('queries JSON paths and renders endian bytes', () {
      expect(
        tools.queryJson(
          '{"users":[{"name":"Alice"},{"name":"Bob"}]}',
          r'$.users[*].name',
        ),
        contains('Alice'),
      );
      expect(tools.endianView('0x12345678'), contains('78 56 34 12'));
    });

    test('JSONPath supports filters, slices, quoted keys and recursion', () {
      const source =
          '{"devices":[{"name":"router","online":true},{"name":"nas","online":false}],"nested":{"name":"child"},"odd.key":7}';
      expect(
        tools.queryJson(source, r'$.devices[?(@.online == true)].name'),
        'router',
      );
      expect(tools.queryJson(source, r'$.devices[0:1].name'), 'router');
      expect(tools.queryJson(source, r"$['odd.key']"), '7');
      expect(tools.queryJson(source, r'$..name'), contains('child'));
    });

    test('calculates future cron runs', () {
      final result = tools.nextCronRuns('*/15 * * * *', count: 2);
      expect(result, contains('每 15 分钟'));
      expect(result, contains('2. '));
      expect(tools.nextCronRuns('@daily', count: 1), contains('0 0 * * *'));
      expect(
        tools.nextCronRuns('0 9 * * MON-FRI', count: 1),
        contains('0 9 * * 1-5'),
      );
    });

    test('user agent parser identifies engines, architecture and WebView', () {
      final desktop = tools.parseUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 Chrome/126.0 Safari/537.36 Edg/126.0',
      );
      expect(desktop, contains('Edge 126.0'));
      expect(desktop, contains('Windows 10/11'));
      expect(desktop, contains('Blink / Chromium'));
      expect(desktop, contains('架构: x64'));
      final webView = tools.parseUserAgent(
        'Mozilla/5.0 (Linux; Android 15; Pixel 9 Build/AP3A; wv) '
        'AppleWebKit/537.36 Version/4.0 Chrome/126.0 Mobile Safari/537.36',
      );
      expect(webView, contains('WebView: 是'));
      expect(webView, contains('设备型号: Pixel 9'));
    });

    test('timestamp inspector detects units and emits all representations', () {
      final seconds = tools.inspectTimestamp('1700000000');
      final milliseconds = tools.inspectTimestamp('1700000000000');
      final iso = tools.inspectTimestamp('2026-07-27T12:00:00+08:00');
      expect(seconds['输入类型'], 'Unix 秒');
      expect(milliseconds['输入类型'], 'Unix 毫秒');
      expect(seconds['Unix 毫秒'], '1700000000000');
      expect(iso['UTC 时间'], startsWith('2026-07-27T04:00:00'));
      expect(
        tools.inspectTimestamps('1700000000\n1700000000000'),
        hasLength(2),
      );
    });

    test('regex tester supports flags, groups and replacement preview', () {
      final matches = tools.testRegex(
        r'^name=(.+)$',
        'NAME=ProtoDeck\nname=toolbox',
        caseSensitive: false,
        multiLine: true,
      );
      expect(matches, hasLength(2));
      expect(matches.last.groups, ['toolbox']);
      expect(
        tools.regexReplace(r'name=(\w+)', 'name=toolbox', r'product=$1'),
        'product=toolbox',
      );
    });

    test('radix converter returns common representations together', () {
      final values = tools.radixRepresentations('FF', 16);
      expect(values['二进制'], '0b11111111');
      expect(values['十进制'], '255');
      expect(values['十六进制'], '0xFF');
    });
  });
}
