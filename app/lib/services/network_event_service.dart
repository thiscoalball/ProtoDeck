import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'linux_network_service.dart';
import 'windows_network_service.dart';

class NetworkEventSnapshot {
  const NetworkEventSnapshot({
    required this.sequence,
    required this.timestamp,
    required this.type,
    required this.connected,
    required this.isDefault,
    required this.transports,
    required this.validated,
    required this.captivePortal,
    required this.partialConnectivity,
    required this.metered,
    required this.addresses,
    required this.dnsServers,
    required this.routes,
    this.interfaceName,
    this.mtu,
    this.ssid,
    this.bssid,
    this.rssi,
    this.frequency,
    this.linkSpeedMbps,
  });

  final int sequence;
  final DateTime timestamp;
  final String type;
  final bool connected;
  final bool isDefault;
  final List<String> transports;
  final bool validated;
  final bool captivePortal;
  final bool partialConnectivity;
  final bool metered;
  final String? interfaceName;
  final int? mtu;
  final List<String> addresses;
  final List<String> dnsServers;
  final List<NetworkRouteSnapshot> routes;
  final String? ssid;
  final String? bssid;
  final int? rssi;
  final int? frequency;
  final int? linkSpeedMbps;

  factory NetworkEventSnapshot.fromMap(Map<Object?, Object?> map) =>
      NetworkEventSnapshot(
        sequence: (map['sequence'] as num?)?.toInt() ?? 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (map['timestampMs'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
        type: map['type'] as String? ?? 'unknown',
        connected: map['connected'] as bool? ?? false,
        isDefault: map['isDefault'] as bool? ?? false,
        transports: (map['transports'] as List<Object?>? ?? const [])
            .map((e) => '$e')
            .toList(growable: false),
        validated: map['validated'] as bool? ?? false,
        captivePortal: map['captivePortal'] as bool? ?? false,
        partialConnectivity: map['partialConnectivity'] as bool? ?? false,
        metered: map['metered'] as bool? ?? false,
        interfaceName: map['interfaceName'] as String?,
        mtu: (map['mtu'] as num?)?.toInt(),
        addresses: (map['addresses'] as List<Object?>? ?? const [])
            .map((value) {
              final item = value as Map<Object?, Object?>;
              return '${item['address']}/${item['prefixLength']}';
            })
            .toList(growable: false),
        dnsServers: (map['dnsServers'] as List<Object?>? ?? const [])
            .map((e) => '$e')
            .toList(growable: false),
        routes: (map['routes'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map(NetworkRouteSnapshot.fromMap)
            .toList(growable: false),
        ssid: map['ssid'] as String?,
        bssid: map['bssid'] as String?,
        rssi: (map['rssi'] as num?)?.toInt(),
        frequency: (map['frequency'] as num?)?.toInt(),
        linkSpeedMbps: (map['linkSpeedMbps'] as num?)?.toInt(),
      );

  List<NetworkChange> changesFrom(NetworkEventSnapshot? previous) {
    if (previous == null) {
      return [
        NetworkChange('网络', '开始观测', connected ? transports.join(' + ') : '未连接'),
      ];
    }
    final changes = <NetworkChange>[];
    void compare(String category, Object? before, Object? after) {
      if ('$before' != '$after')
        changes.add(NetworkChange(category, _shown(before), _shown(after)));
    }

    compare('连接', previous.connected, connected);
    compare('默认路由', previous.transports.join(' + '), transports.join(' + '));
    compare('接口', previous.interfaceName, interfaceName);
    compare('互联网验证', previous.validated, validated);
    compare('登录门户', previous.captivePortal, captivePortal);
    compare('地址', previous.addresses.join(', '), addresses.join(', '));
    compare('DNS', previous.dnsServers.join(', '), dnsServers.join(', '));
    compare(
      '网关',
      previous.defaultGateways.join(', '),
      defaultGateways.join(', '),
    );
    compare('MTU', previous.mtu, mtu);
    compare('Wi-Fi SSID', previous.ssid, ssid);
    compare('Wi-Fi BSSID', previous.bssid, bssid);
    if (changes.isEmpty && type == 'losing')
      changes.add(const NetworkChange('网络', '可用', '即将丢失'));
    return changes;
  }

  List<String> get defaultGateways => routes
      .where((route) => route.isDefault && route.gateway?.isNotEmpty == true)
      .map((route) => route.gateway!)
      .toList(growable: false);
}

class NetworkRouteSnapshot {
  const NetworkRouteSnapshot({
    required this.destination,
    required this.isDefault,
    this.gateway,
  });
  final String destination;
  final String? gateway;
  final bool isDefault;
  factory NetworkRouteSnapshot.fromMap(Map<Object?, Object?> map) =>
      NetworkRouteSnapshot(
        destination: map['destination'] as String? ?? '',
        gateway: map['gateway'] as String?,
        isDefault: map['default'] as bool? ?? false,
      );
}

class NetworkChange {
  const NetworkChange(this.category, this.before, this.after);
  final String category;
  final String before;
  final String after;
}

class NetworkEventRecord {
  const NetworkEventRecord(this.snapshot, this.change);
  final NetworkEventSnapshot snapshot;
  final NetworkChange change;
}

/// Process-local network event session. Monitoring continues while UI pages
/// detach and stops only through [stop] or process termination.
class NetworkEventSession {
  NetworkEventSession._();

  static final NetworkEventSession instance = NetworkEventSession._();

  final _changes = StreamController<void>.broadcast(sync: true);
  final _events = <NetworkEventRecord>[];
  StreamSubscription<NetworkEventSnapshot>? _subscription;
  NetworkEventSnapshot? _current;
  Object? _error;
  bool _running = false;

  Stream<void> get changes => _changes.stream;
  List<NetworkEventRecord> get events => List.unmodifiable(_events);
  NetworkEventSnapshot? get current => _current;
  Object? get error => _error;
  bool get running => _running;

  void start() {
    if (_running) return;
    _running = true;
    _error = null;
    _notify();
    _subscription = NetworkEventService().watch().listen(
      (snapshot) {
        final previous = _current;
        _current = snapshot;
        for (final change in snapshot.changesFrom(previous)) {
          if (_events.length >= 2000) _events.removeAt(0);
          _events.add(NetworkEventRecord(snapshot, change));
        }
        _notify();
      },
      onError: (Object error) {
        _error = error;
        _notify();
      },
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _running = false;
    _notify();
  }

  void clear() {
    _events.clear();
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }
}

class NetworkEventService {
  static const _events = EventChannel('nettools/network_events');

  Stream<NetworkEventSnapshot> watch() {
    if (Platform.isWindows) {
      return WindowsNetworkBridge.instance.watchNetworkEvents().map(
        NetworkEventSnapshot.fromMap,
      );
    }
    if (Platform.isLinux) {
      return LinuxNetworkBridge.instance.watchNetworkEvents().map(
        NetworkEventSnapshot.fromMap,
      );
    }
    return _events
        .receiveBroadcastStream()
        .where((value) => value is Map)
        .map(
          (value) =>
              NetworkEventSnapshot.fromMap(value as Map<Object?, Object?>),
        );
  }
}

String _shown(Object? value) {
  if (value == null || '$value'.isEmpty) return '无';
  if (value == true) return '是';
  if (value == false) return '否';
  return '$value';
}
