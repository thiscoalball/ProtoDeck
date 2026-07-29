import 'dart:async';

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
    this.localIpv4,
    this.dnsSignature = '',
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
  final String? localIpv4;
  final String dnsSignature;
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
    this.fromChannel,
    this.toChannel,
    this.fromFrequency,
    this.toFrequency,
    this.addressChanged = false,
    this.gatewayChanged = false,
    this.dnsChanged = false,
  });
  final DateTime changedAt;
  final String fromBssid;
  final String toBssid;
  final int? fromRssi;
  final int? toRssi;
  final Duration? observedOutage;
  final Duration? recoveryTime;
  final int lostProbes;
  final int? fromChannel;
  final int? toChannel;
  final int? fromFrequency;
  final int? toFrequency;
  final bool addressChanged;
  final bool gatewayChanged;
  final bool dnsChanged;
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
      localIpv4: context.lanAddresses
          .where((value) => value.family == 'IPv4')
          .map((value) => value.address)
          .firstOrNull,
      dnsSignature: (context.dnsServers.toList()..sort()).join(','),
    );
  }
}

/// Retains roaming samples and probe state while the page is not visible.
class WifiRoamingSession {
  WifiRoamingSession._();

  static final WifiRoamingSession instance = WifiRoamingSession._();

  final _service = WifiRoamingService();
  final _changes = StreamController<void>.broadcast(sync: true);
  WifiRoamTracker _tracker = WifiRoamTracker();
  final _samples = <WifiRoamSample>[];
  final _events = <WifiRoamEvent>[];
  Timer? _timer;
  bool _running = false;
  bool _sampling = false;
  Object? _error;

  Stream<void> get changes => _changes.stream;
  List<WifiRoamSample> get samples => List.unmodifiable(_samples);
  List<WifiRoamEvent> get events => List.unmodifiable(_events);
  bool get running => _running;
  Object? get error => _error;

  void start() {
    if (_running) return;
    _running = true;
    _error = null;
    _samples.clear();
    _events.clear();
    _tracker = WifiRoamTracker();
    _notify();
    unawaited(_sample());
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_sample()),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _notify();
  }

  Future<void> _sample() async {
    if (!_running || _sampling) return;
    _sampling = true;
    try {
      final sample = await _service.sample();
      if (!_running) return;
      final event = _tracker.add(sample);
      _samples.add(sample);
      if (_samples.length > 120) _samples.removeAt(0);
      if (event != null) _events.add(event);
      _error = sample.bssid == null
          ? '当前 BSSID 不可用，请确认附近设备/定位权限与系统定位服务。'
          : null;
      _notify();
    } on Object catch (error) {
      _error = error;
      _notify();
    } finally {
      _sampling = false;
    }
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
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
        fromChannel: previous.channel,
        toChannel: sample.channel,
        fromFrequency: previous.frequency,
        toFrequency: sample.frequency,
        addressChanged: previous.localIpv4 != sample.localIpv4,
        gatewayChanged: previous.gateway != sample.gateway,
        dnsChanged: previous.dnsSignature != sample.dnsSignature,
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
          fromChannel: pending.fromChannel,
          toChannel: pending.toChannel,
          fromFrequency: pending.fromFrequency,
          toFrequency: pending.toFrequency,
          addressChanged: pending.addressChanged,
          gatewayChanged: pending.gatewayChanged,
          dnsChanged: pending.dnsChanged,
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
    required this.fromChannel,
    required this.toChannel,
    required this.fromFrequency,
    required this.toFrequency,
    required this.addressChanged,
    required this.gatewayChanged,
    required this.dnsChanged,
    required this.lastSuccessBefore,
  });
  final DateTime changedAt;
  final String fromBssid;
  final String toBssid;
  final int? fromRssi;
  final int? toRssi;
  final int? fromChannel;
  final int? toChannel;
  final int? fromFrequency;
  final int? toFrequency;
  final bool addressChanged;
  final bool gatewayChanged;
  final bool dnsChanged;
  final DateTime? lastSuccessBefore;
  int lostProbes = 0;
}

extension _FirstOrNullRoam<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
