import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/models/network_context.dart';
import 'package:nettools_mobile/services/wifi_analysis_service.dart';

void main() {
  WifiAccessPoint accessPoint({
    String bssid = 'AA:BB:CC:DD:EE:FF',
    int rssi = -60,
    int frequency = 2412,
    int channel = 1,
    String width = '20 MHz',
    int timestamp = 10,
    int? utilization,
    String security = '[WPA2-PSK-CCMP][ESS]',
    List<String> securityTypes = const [],
  }) => WifiAccessPoint(
    ssid: 'Lab',
    bssid: bssid,
    rssi: rssi,
    signalLevel: 3,
    frequency: frequency,
    channel: channel,
    channelWidth: width,
    security: security,
    timestampMicros: timestamp,
    channelUtilizationPercent: utilization,
    securityTypes: securityTypes,
  );

  test('signal monitor does not duplicate the same radio sample', () {
    final monitor = WifiSignalMonitor();
    final snapshot = WifiScanSnapshot(
      accessPoints: [accessPoint()],
      fresh: true,
      requested: true,
      status: 'fresh',
      collectedAt: DateTime(2026),
    );
    expect(monitor.addSnapshot(snapshot), isTrue);
    expect(monitor.addSnapshot(snapshot), isFalse);
    expect(monitor.samples.values.single, hasLength(1));
  });

  test('channel advisor accounts for width, RSSI and BSS load', () {
    final results = const WifiChannelAdvisor().recommend(
      accessPoints: [
        accessPoint(rssi: -35, utilization: 90),
        accessPoint(
          bssid: '11:22:33:44:55:66',
          rssi: -75,
          frequency: 2437,
          channel: 6,
        ),
      ],
      minimumFrequency: 2400,
      maximumFrequency: 2500,
      usableFrequencies: const [2412, 2437, 2462],
    );
    expect(results.first.channel, 11);
    expect(results.first.confidence, 'medium');
    expect(results.last.channel, 1);
  });

  test('security analyzer warns about same-SSID mismatch', () {
    final selected = accessPoint();
    final other = accessPoint(
      bssid: '11:22:33:44:55:66',
      security: '[ESS]',
      securityTypes: const ['Open'],
    );
    final findings = const WifiSecurityAnalyzer().inspect(
      selected,
      sameSsid: [selected, other],
    );
    expect(findings.map((value) => value.id), contains('ssidSecurityMismatch'));
  });

  test('radio quality exposes honest scoring components', () {
    final result = const WifiRadioQualityEvaluator().evaluate(
      rssi: -58,
      linkSpeedMbps: 866,
      accessPoint: accessPoint(
        bssid: 'AA:BB:CC:DD:EE:20',
        frequency: 5180,
        rssi: -58,
        width: '80 MHz',
        utilization: 20,
      ),
    );
    expect(result.score, greaterThanOrEqualTo(75));
    expect(result.signalScore, inInclusiveRange(0, 60));
    expect(result.congestionScore, 20);
    expect(result.linkScore, 13);
    expect(result.notes.last, contains('不代表'));
  });
}
