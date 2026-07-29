import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/wifi_quality_service.dart';

void main() {
  test(
    'a reachable LAN without validated Internet is local-only, not offline',
    () {
      final state = WifiConnectionQualityService.classify(
        connected: true,
        gatewayReachable: true,
        dnsReachable: false,
        validated: false,
        captivePortal: false,
      );
      expect(state, WifiConnectionState.localOnly);
    },
  );

  test('validated link with working DNS is Internet healthy', () {
    final state = WifiConnectionQualityService.classify(
      connected: true,
      gatewayReachable: true,
      dnsReachable: true,
      validated: true,
      captivePortal: false,
    );
    expect(state, WifiConnectionState.internetHealthy);
  });

  test('captive portal is reported as degraded', () {
    final state = WifiConnectionQualityService.classify(
      connected: true,
      gatewayReachable: true,
      dnsReachable: true,
      validated: false,
      captivePortal: true,
    );
    expect(state, WifiConnectionState.degraded);
  });
}
