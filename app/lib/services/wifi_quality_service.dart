import 'dart:async';
import 'dart:io';

import '../models/network_context.dart';
import 'native_network_service.dart';

enum WifiConnectionState { internetHealthy, localOnly, degraded, offline }

class WifiConnectionQualityReport {
  const WifiConnectionQualityReport({
    required this.state,
    required this.gatewayReachable,
    required this.gatewayLatencyMs,
    required this.dnsReachable,
    required this.dnsLatencyMs,
    required this.validated,
    required this.captivePortal,
    required this.ipv4Available,
    required this.ipv6Available,
  });

  final WifiConnectionState state;
  final bool gatewayReachable;
  final double? gatewayLatencyMs;
  final bool dnsReachable;
  final double? dnsLatencyMs;
  final bool validated;
  final bool captivePortal;
  final bool ipv4Available;
  final bool ipv6Available;
}

typedef WifiGatewayProbe = Future<NativeCommandResult> Function(String gateway);
typedef WifiDnsProbe = Future<List<InternetAddress>> Function(String host);

class WifiConnectionQualityService {
  const WifiConnectionQualityService();

  Future<WifiConnectionQualityReport> probe(
    NetworkContext context, {
    required WifiGatewayProbe pingGateway,
    WifiDnsProbe dnsLookup = InternetAddress.lookup,
  }) async {
    final gateway =
        context.lanGateways.firstOrNull ?? context.gateways.firstOrNull;
    var gatewayReachable = false;
    double? gatewayLatency;
    if (gateway != null) {
      final watch = Stopwatch()..start();
      try {
        final response = await pingGateway(
          gateway,
        ).timeout(const Duration(seconds: 4));
        watch.stop();
        gatewayReachable = response.exitCode == 0;
        gatewayLatency =
            _latency(response.output) ??
            (gatewayReachable ? watch.elapsedMicroseconds / 1000 : null);
      } on Object {
        watch.stop();
      }
    }

    var dnsReachable = false;
    double? dnsLatency;
    final dnsWatch = Stopwatch()..start();
    try {
      final addresses = await dnsLookup(
        'example.com',
      ).timeout(const Duration(seconds: 4));
      dnsWatch.stop();
      dnsReachable = addresses.isNotEmpty;
      dnsLatency = dnsWatch.elapsedMicroseconds / 1000;
    } on Object {
      dnsWatch.stop();
    }

    final ipv4 = context.addresses.any((value) => value.family == 'IPv4');
    final ipv6 = context.addresses.any(
      (value) => value.family == 'IPv6' && !value.address.startsWith('fe80:'),
    );
    return WifiConnectionQualityReport(
      state: classify(
        connected: context.connected,
        gatewayReachable: gatewayReachable,
        dnsReachable: dnsReachable,
        validated: context.validated,
        captivePortal: context.captivePortal,
      ),
      gatewayReachable: gatewayReachable,
      gatewayLatencyMs: gatewayLatency,
      dnsReachable: dnsReachable,
      dnsLatencyMs: dnsLatency,
      validated: context.validated,
      captivePortal: context.captivePortal,
      ipv4Available: ipv4,
      ipv6Available: ipv6,
    );
  }

  static WifiConnectionState classify({
    required bool connected,
    required bool gatewayReachable,
    required bool dnsReachable,
    required bool validated,
    required bool captivePortal,
  }) {
    if (!connected || (!gatewayReachable && !dnsReachable && !validated)) {
      return WifiConnectionState.offline;
    }
    if (validated && dnsReachable && !captivePortal) {
      return WifiConnectionState.internetHealthy;
    }
    if (gatewayReachable && !validated && !captivePortal) {
      return WifiConnectionState.localOnly;
    }
    return WifiConnectionState.degraded;
  }

  static double? _latency(String output) {
    final values = RegExp(r'time[=<]\s*([0-9.]+)\s*ms', caseSensitive: false)
        .allMatches(output)
        .map((match) => double.tryParse(match.group(1) ?? ''))
        .whereType<double>()
        .toList(growable: false);
    if (values.isEmpty) return null;
    return values.reduce((left, right) => left + right) / values.length;
  }
}

extension _FirstOrNullQuality<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
