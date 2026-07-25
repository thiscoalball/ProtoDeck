import 'native_network_service.dart';

class WifiRoamSample {
  const WifiRoamSample({
    required this.timestamp,
    required this.ssid,
    required this.bssid,
    required this.rssi,
    required this.frequency,
    required this.channel,
    required this.linkSpeedMbps,
    required this.gateway,
    required this.gatewayRttMs,
    required this.gatewayReachable,
  });

  final DateTime timestamp;
  final String? ssid;
  final String? bssid;
  final int? rssi;
  final int? frequency;
  final int? channel;
  final int? linkSpeedMbps;
  final String? gateway;
  final double? gatewayRttMs;
  final bool gatewayReachable;
}

class WifiRoamEvent {
  const WifiRoamEvent({
    required this.changedAt,
    required this.fromBssid,
    required this.toBssid,
    required this.fromRssi,
    required this.toRssi,
    required this.observedOutage,
    required this.recoveryTime,
    required this.lostProbes,
  });
  final DateTime changedAt;
  final String fromBssid;
  final String toBssid;
  final int? fromRssi;
  final int? toRssi;
  final Duration? observedOutage;
  final Duration? recoveryTime;
  final int lostProbes;
}

class WifiRoamingService {
  WifiRoamingService({NativeNetworkService? native})
    : _native = native ?? NativeNetworkService();
  final NativeNetworkService _native;

  Future<WifiRoamSample> sample() async {
    final context = await _native.getNetworkContext();
    final wifi = context.wifi;
    final gateway =
        context.lanGateways.firstOrNull ?? context.gateways.firstOrNull;
    double? rtt;
    var reachable = false;
    if (gateway != null) {
      try {
        final response = await _native.runPing(
          host: gateway,
          count: 1,
          timeoutMs: 900,
          intervalMs: 250,
          packetSize: 32,
        );
        reachable = response.exitCode == 0;
        final match = RegExp(
          r'time[=<]([0-9.]+)\s*ms',
          caseSensitive: false,
        ).firstMatch(response.output);
        rtt = double.tryParse(match?.group(1) ?? '');
        if (reachable && rtt == null && response.output.contains('time<1'))
          rtt = .5;
      } on Object {
        reachable = false;
      }
    }
    return WifiRoamSample(
      timestamp: DateTime.now(),
      ssid: wifi?.ssid,
      bssid: wifi?.bssid,
      rssi: wifi?.rssi,
      frequency: wifi?.frequency,
      channel: wifi?.channel,
      linkSpeedMbps: wifi?.linkSpeedMbps,
      gateway: gateway,
      gatewayRttMs: rtt,
      gatewayReachable: reachable,
    );
  }
}

class WifiRoamTracker {
  WifiRoamSample? _previous;
  DateTime? _lastSuccess;
  _PendingRoam? _pending;

  WifiRoamEvent? add(WifiRoamSample sample) {
    final previous = _previous;
    if (previous != null &&
        previous.ssid != null &&
        previous.ssid == sample.ssid &&
        previous.bssid != null &&
        sample.bssid != null &&
        previous.bssid != sample.bssid) {
      _pending = _PendingRoam(
        changedAt: sample.timestamp,
        fromBssid: previous.bssid!,
        toBssid: sample.bssid!,
        fromRssi: previous.rssi,
        toRssi: sample.rssi,
        lastSuccessBefore: _lastSuccess,
      );
    }
    if (!sample.gatewayReachable) _pending?.lostProbes++;
    WifiRoamEvent? completed;
    if (sample.gatewayReachable) {
      final pending = _pending;
      if (pending != null) {
        completed = WifiRoamEvent(
          changedAt: pending.changedAt,
          fromBssid: pending.fromBssid,
          toBssid: pending.toBssid,
          fromRssi: pending.fromRssi,
          toRssi: pending.toRssi,
          observedOutage: pending.lastSuccessBefore == null
              ? null
              : sample.timestamp.difference(pending.lastSuccessBefore!),
          recoveryTime: sample.timestamp.difference(pending.changedAt),
          lostProbes: pending.lostProbes,
        );
        _pending = null;
      }
      _lastSuccess = sample.timestamp;
    }
    _previous = sample;
    return completed;
  }
}

class _PendingRoam {
  _PendingRoam({
    required this.changedAt,
    required this.fromBssid,
    required this.toBssid,
    required this.fromRssi,
    required this.toRssi,
    required this.lastSuccessBefore,
  });
  final DateTime changedAt;
  final String fromBssid;
  final String toBssid;
  final int? fromRssi;
  final int? toRssi;
  final DateTime? lastSuccessBefore;
  int lostProbes = 0;
}

extension _FirstOrNullRoam<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
