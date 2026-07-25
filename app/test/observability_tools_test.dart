import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/models/structured_payload.dart';
import 'package:nettools_mobile/services/api_rule_engine.dart';
import 'package:nettools_mobile/services/api_workbench_service.dart';
import 'package:nettools_mobile/services/pcap_analysis_service.dart';
import 'package:nettools_mobile/services/syslog_receiver_service.dart';
import 'package:nettools_mobile/services/wifi_roaming_service.dart';
import 'package:nettools_mobile/ui/widgets/structured_data_viewer.dart';

void main() {
  test('API rules assert and extract one shared JSONPath value', () {
    final response = ApiResponseData(
      statusCode: 200,
      reason: 'OK',
      headers: const {
        'content-type': ['application/json'],
        'x-request-id': ['abc-123'],
      },
      body: '{"data":{"token":"secret-token","items":[{"id":7}]}}',
      elapsed: const Duration(milliseconds: 42),
      bytes: 60,
      finalUrl: Uri.parse('https://example.com/api'),
      rawBytes: Uint8List(0),
      cookies: [Cookie('session', 'cookie-value')],
      requestMethod: 'GET',
      requestHeaders: const {},
      requestBody: '',
    );
    final run = ApiRuleEngine().evaluate(
      response,
      assertions: const [
        ApiAssertionRule(
          type: ApiAssertionType.statusRange,
          expected: '200-299',
        ),
        ApiAssertionRule(
          type: ApiAssertionType.jsonPathEquals,
          selector: r'$.data.items[0].id',
          expected: '7',
        ),
      ],
      extractions: const [
        ApiExtractionRule(
          variable: 'token',
          source: ApiExtractionSource.jsonPath,
          selector: r'$.data.token',
        ),
      ],
    );
    expect(run.assertions.every((result) => result.passed), isTrue);
    expect(run.extractions.single.value, 'secret-token');
  });

  test('Syslog parser separates RFC5424 metadata and JSON message', () {
    final message = parseSyslog(
      '<165>1 2026-07-25T10:00:00Z router dhcpd 42 lease '
      '[meta zone="lan"] {"ip":"192.0.2.10"}',
      address: '192.0.2.1',
    );
    expect(message.standard, 'RFC 5424');
    expect(message.facility, 20);
    expect(message.severity, 5);
    expect(message.hostname, 'router');
    expect(message.appName, 'dhcpd');
    expect(message.structuredData, '[meta zone="lan"]');
    expect(StructuredPayload(rawText: message.message).isJson, isTrue);
  });

  test('Wi-Fi roam tracker measures the observed outage window', () {
    final tracker = WifiRoamTracker();
    final start = DateTime.utc(2026, 7, 25, 10);
    expect(tracker.add(_sample(start, 'aa', true)), isNull);
    expect(
      tracker.add(_sample(start.add(const Duration(seconds: 2)), 'bb', false)),
      isNull,
    );
    final event = tracker.add(
      _sample(start.add(const Duration(seconds: 4)), 'bb', true),
    );
    expect(event, isNotNull);
    expect(event!.fromBssid, 'aa');
    expect(event.toBssid, 'bb');
    expect(event.observedOutage, const Duration(seconds: 4));
    expect(event.recoveryTime, const Duration(seconds: 2));
    expect(event.lostProbes, 1);
  });

  test('PCAP parser decodes an Ethernet IPv4 UDP DNS packet', () async {
    final directory = await Directory.systemTemp.createTemp('pcap-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/sample.pcap');
    await file.writeAsBytes(_pcapFixture());
    final analysis = await PcapAnalysisService().analyze(file.path);
    expect(analysis.format, 'PCAP');
    expect(analysis.packetCount, 1);
    expect(analysis.packets.single.networkProtocol, 'IPv4');
    expect(analysis.packets.single.transportProtocol, 'UDP');
    expect(analysis.packets.single.applicationProtocol, 'DNS');
    expect(analysis.packets.single.applicationDetail, 'Query A example.com');
    expect(analysis.packets.single.source, '192.0.2.10');
    expect(analysis.packets.single.destination, '198.51.100.53');
    expect(
      analysis.protocolHierarchy.map((item) => item.path.join('/')),
      containsAll(<String>['IPv4', 'IPv4/UDP', 'IPv4/UDP/DNS']),
    );
    expect(analysis.protocolHierarchy.last.byteCount, greaterThan(0));
    expect(analysis.ioBuckets, hasLength(1));
    expect(analysis.ioBuckets.single.packetCount, 1);
    expect(
      analysis.endpoints.keys,
      containsAll(['192.0.2.10', '198.51.100.53']),
    );
    expect(analysis.flows, hasLength(1));
    expect(analysis.flows.single.protocol, 'DNS');
    expect(analysis.flows.single.packetCount, 1);
    expect(analysis.flows.single.byteCount, 71);
    expect(analysis.flows.single.details, contains('Query A example.com'));
  });

  testWidgets('structured viewer exposes tree, code, raw and hex modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: StructuredDataViewer(
              payload: StructuredPayload(
                rawText: '{"name":"ProtoDeck","ok":true,"count":3}',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('树形'), findsOneWidget);
    expect(find.text('代码'), findsOneWidget);
    expect(find.text('原始'), findsOneWidget);
    expect(find.text('Hex'), findsOneWidget);
    expect(find.textContaining('"name"'), findsOneWidget);
    await tester.tap(find.text('树形'));
    await tester.pump();
    expect(find.textContaining('name:'), findsOneWidget);
  });

  test('structured payload detects and formats JSON, XML, HTML and text', () {
    final json = StructuredPayload(
      rawText: 'null',
      contentType: 'application/json; charset=utf-8',
    );
    expect(json.isJson, isTrue);
    expect(json.formattedText, 'null');

    final xml = StructuredPayload(
      rawText: '<root><item id="1">value</item></root>',
      contentType: 'application/xml',
    );
    expect(xml.format, StructuredPayloadFormat.xml);
    expect(xml.parseError, isNull);
    expect(xml.formattedText, contains('\n  <item'));

    final html = StructuredPayload(
      rawText: '<!doctype html><html><body><h1>Hello</h1></body></html>',
      contentType: 'text/html; charset=UTF-8',
    );
    expect(html.format, StructuredPayloadFormat.html);
    expect(html.parseError, isNull);
    expect(html.formattedText, contains('<body>'));

    final text = StructuredPayload(
      rawText: '200 OK\nserver ready',
      contentType: 'text/plain',
    );
    expect(text.format, StructuredPayloadFormat.text);
    expect(text.parseError, isNull);
    expect(text.formattedText, text.rawText);
  });

  test('only JSON-shaped invalid content exposes a JSON parse error', () {
    final html = StructuredPayload(
      rawText: '<html><p>not json</p></html>',
      contentType: 'text/html',
    );
    expect(html.parseError, isNull);

    final invalidJson = StructuredPayload(
      rawText: '{"missing":}',
      contentType: 'application/json',
    );
    expect(invalidJson.format, StructuredPayloadFormat.json);
    expect(invalidJson.parseError, isNotNull);
  });

  testWidgets('XML response opens in formatted mode without JSON error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: StructuredDataViewer(
              payload: StructuredPayload(
                rawText: '<response><status>ok</status></response>',
                contentType: 'application/xml',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('格式化'), findsOneWidget);
    expect(find.textContaining('不是有效 JSON'), findsNothing);
    expect(find.textContaining('<response>'), findsOneWidget);
  });
}

WifiRoamSample _sample(DateTime time, String bssid, bool reachable) =>
    WifiRoamSample(
      timestamp: time,
      ssid: 'test',
      bssid: bssid,
      rssi: bssid == 'aa' ? -65 : -50,
      frequency: 5180,
      channel: 36,
      linkSpeedMbps: 1200,
      gateway: '192.0.2.1',
      gatewayRttMs: reachable ? 2 : null,
      gatewayReachable: reachable,
    );

Uint8List _pcapFixture() {
  const dnsQuery = <int>[
    0x12,
    0x34,
    0x01,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x07,
    0x65,
    0x78,
    0x61,
    0x6d,
    0x70,
    0x6c,
    0x65,
    0x03,
    0x63,
    0x6f,
    0x6d,
    0x00,
    0x00,
    0x01,
    0x00,
    0x01,
  ];
  final packet = Uint8List(42 + dnsQuery.length);
  packet.setRange(0, 12, List<int>.filled(12, 1));
  packet[12] = 0x08;
  packet[13] = 0x00;
  packet[14] = 0x45;
  packet[16] = 0;
  packet[17] = 28 + dnsQuery.length;
  packet[23] = 17;
  packet.setRange(26, 30, [192, 0, 2, 10]);
  packet.setRange(30, 34, [198, 51, 100, 53]);
  packet[34] = 0x30;
  packet[35] = 0x39;
  packet[36] = 0;
  packet[37] = 53;
  packet[38] = 0;
  packet[39] = 8 + dnsQuery.length;
  packet.setRange(42, packet.length, dnsQuery);

  final output = Uint8List(24 + 16 + packet.length);
  final data = ByteData.sublistView(output);
  data.setUint32(0, 0xA1B2C3D4, Endian.little);
  data.setUint16(4, 2, Endian.little);
  data.setUint16(6, 4, Endian.little);
  data.setUint32(16, 65535, Endian.little);
  data.setUint32(20, 1, Endian.little);
  data.setUint32(24, 1, Endian.little);
  data.setUint32(28, 500000, Endian.little);
  data.setUint32(32, packet.length, Endian.little);
  data.setUint32(36, packet.length, Endian.little);
  output.setRange(40, output.length, packet);
  return output;
}
