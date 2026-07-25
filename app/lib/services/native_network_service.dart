import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

import '../models/network_context.dart';
import 'linux_network_service.dart';
import 'windows_network_service.dart';

class NativeNetworkService {
  static const _channel = MethodChannel('nettools/native');
  static final _windows = WindowsNetworkBridge.instance;
  static final _linux = LinuxNetworkBridge.instance;
  static bool get _desktop => Platform.isWindows || Platform.isLinux;

  Future<NetworkContext> getNetworkContext() async {
    final map = Platform.isWindows
        ? await _windows.getNetworkContext()
        : Platform.isLinux
        ? await _linux.getNetworkContext()
        : await _channel.invokeMapMethod<Object?, Object?>('getNetworkContext');
    if (map == null) throw StateError('当前平台未返回网络信息');
    return NetworkContext.fromMap(map);
  }

  Future<List<WifiAccessPoint>> scanWifi() async {
    return (await scanWifiSnapshot()).accessPoints;
  }

  Future<WifiScanSnapshot> scanWifiSnapshot() async {
    final map = Platform.isWindows
        ? await _windows.scanWifiSnapshot()
        : Platform.isLinux
        ? await _linux.scanWifiSnapshot()
        : await _channel.invokeMapMethod<Object?, Object?>('scanWifi');
    if (map == null) throw StateError('当前平台未返回 Wi‑Fi 扫描结果');
    return WifiScanSnapshot.fromMap(map);
  }

  Future<TrafficSnapshot> getTrafficSnapshot() async {
    final map = Platform.isWindows
        ? await _windows.getTrafficSnapshot()
        : Platform.isLinux
        ? await _linux.getTrafficSnapshot()
        : await _channel.invokeMapMethod<Object?, Object?>(
            'getTrafficSnapshot',
          );
    if (map == null) throw StateError('当前平台未返回流量快照');
    return TrafficSnapshot.fromMap(map);
  }

  Future<bool> hasUsageStatsAccess() async => _desktop
      ? true
      : await _channel.invokeMethod<bool>('hasUsageStatsAccess') ?? false;

  Future<void> openUsageStatsSettings() => _desktop
      ? Future<void>.value()
      : _channel.invokeMethod<void>('openUsageStatsSettings');

  Future<List<AppTrafficUsage>> getAppTrafficStats({DateTime? since}) async {
    if (_desktop) {
      final snapshot = await getTrafficSnapshot();
      final grouped = <String, List<TrafficConnection>>{};
      for (final connection in snapshot.connections) {
        final key = connection.processId == null
            ? 'uid:${connection.uid ?? -1}'
            : 'pid:${connection.processId}';
        grouped.putIfAbsent(key, () => []).add(connection);
      }
      final rows = grouped.entries.map((entry) {
        final sample = entry.value.first;
        final identifier = sample.processId ?? sample.uid ?? -1;
        return AppTrafficUsage(
          uid: identifier,
          label:
              sample.applicationLabel ??
              sample.processName ??
              (sample.uid == null ? 'Unknown process' : 'UID ${sample.uid}'),
          packageName: sample.packageName,
          rxBytes: 0,
          txBytes: 0,
          connectionCount: entry.value.length,
          confidence: 'ownership',
          executablePath: sample.executablePath,
        );
      }).toList();
      rows.sort((a, b) => b.connectionCount.compareTo(a.connectionCount));
      return rows;
    }
    final rows = await _channel.invokeListMethod<Object?>(
      'getAppTrafficStats',
      {
        'sinceMs': (since ?? DateTime.now().subtract(const Duration(hours: 1)))
            .millisecondsSinceEpoch,
      },
    );
    return (rows ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(AppTrafficUsage.fromMap)
        .toList(growable: false);
  }

  Future<NativeCommandResult> runPing({
    required String host,
    int count = 4,
    int timeoutMs = 2000,
    int intervalMs = 1000,
    int packetSize = 56,
    bool? ipv6,
  }) async {
    final arguments = {
      'host': host,
      'count': count,
      'timeoutMs': timeoutMs,
      'intervalMs': intervalMs,
      'packetSize': packetSize,
      'ipv6': ipv6,
    };
    final map = Platform.isWindows
        ? await _windows.runPing(
            host: host,
            count: count,
            timeoutMs: timeoutMs,
            packetSize: packetSize,
            ipv6: ipv6,
          )
        : Platform.isLinux
        ? await _linux.runPing(
            host: host,
            count: count,
            timeoutMs: timeoutMs,
            intervalMs: intervalMs,
            packetSize: packetSize,
            ipv6: ipv6,
          )
        : await _channel.invokeMapMethod<Object?, Object?>(
            'runPing',
            arguments,
          );
    if (map == null) throw StateError('当前平台未返回 Ping 结果');
    return NativeCommandResult(
      exitCode: map['exitCode'] as int? ?? -1,
      output: map['output'] as String? ?? '',
      command: map['command'] as String? ?? '',
    );
  }

  Future<PathMtuResult> probePathMtu({
    required String host,
    required int interfaceMtu,
    bool? ipv6,
    int timeoutMs = 1600,
  }) async {
    final map = Platform.isWindows
        ? await _windows.probePathMtu(
            host: host,
            interfaceMtu: interfaceMtu,
            ipv6: ipv6 ?? false,
            timeoutMs: timeoutMs,
          )
        : Platform.isLinux
        ? await _linux.probePathMtu(
            host: host,
            interfaceMtu: interfaceMtu,
            ipv6: ipv6 ?? false,
            timeoutMs: timeoutMs,
          )
        : await _channel.invokeMapMethod<Object?, Object?>('probePathMtu', {
            'host': host,
            'interfaceMtu': interfaceMtu,
            'ipv6': ipv6,
            'timeoutMs': timeoutMs,
          });
    if (map == null) throw StateError('当前平台未返回路径 MTU 结果');
    return PathMtuResult.fromMap(map);
  }

  Future<List<NativeTraceHop>> runTraceroute({
    required String host,
    int maxHops = 30,
    int timeoutMs = 1800,
    int probes = 3,
    bool resolveHostnames = true,
  }) async {
    final rows = Platform.isWindows
        ? await _windows.runTraceroute(
            host: host,
            maxHops: maxHops,
            timeoutMs: timeoutMs,
            resolveHostnames: resolveHostnames,
          )
        : Platform.isLinux
        ? await _linux.runTraceroute(
            host: host,
            maxHops: maxHops,
            timeoutMs: timeoutMs,
            probes: probes,
            resolveHostnames: resolveHostnames,
          )
        : await _channel.invokeListMethod<Object?>('runTraceroute', {
            'host': host,
            'maxHops': maxHops,
            'timeoutMs': timeoutMs,
            'probes': probes,
            'resolveHostnames': resolveHostnames,
          });
    final hops =
        (rows ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map(NativeTraceHop.fromMap)
            .where((hop) => hop.hop > 0)
            .toList(growable: true)
          ..sort((a, b) => a.hop.compareTo(b.hop));
    return List.unmodifiable(hops);
  }

  Future<void> cancelTraceroute() => Platform.isWindows
      ? _windows.cancelTraceroute()
      : Platform.isLinux
      ? _linux.cancelTraceroute()
      : _channel.invokeMethod<void>('cancelTraceroute');

  Future<IperfNativeResult> runIperf(List<String> arguments) async {
    final encoded = Platform.isWindows
        ? await _windows.runIperf(arguments)
        : Platform.isLinux
        ? await _linux.runIperf(arguments)
        : await _channel.invokeMethod<String>('runIperf', {
            'arguments': arguments,
          });
    if (encoded == null) throw StateError('当前平台未返回 iPerf 结果');
    final value = jsonDecode(encoded) as Map<String, Object?>;
    return IperfNativeResult(
      ok: value['ok'] as bool? ?? false,
      exitCode: value['exitCode'] as int? ?? -1,
      output: value['output'] as String? ?? '',
    );
  }

  Future<bool> stopIperf() async => Platform.isWindows
      ? _windows.stopIperf()
      : Platform.isLinux
      ? _linux.stopIperf()
      : await _channel.invokeMethod<bool>('stopIperf') ?? false;

  Future<bool> isIperfRunning() async => Platform.isWindows
      ? _windows.isIperfRunning
      : Platform.isLinux
      ? _linux.isIperfRunning
      : await _channel.invokeMethod<bool>('isIperfRunning') ?? false;

  Future<String?> pollIperfEvent() => Platform.isWindows
      ? Future.value(_windows.pollIperfEvent())
      : Platform.isLinux
      ? Future.value(_linux.pollIperfEvent())
      : _channel.invokeMethod<String>('pollIperfEvent');

  Future<void> startForegroundTask(String title, String detail) => _desktop
      ? Future<void>.value()
      : _channel.invokeMethod<void>('startForegroundTask', {
          'title': title,
          'detail': detail,
        });

  Future<void> stopForegroundTask() => _desktop
      ? Future<void>.value()
      : _channel.invokeMethod<void>('stopForegroundTask');

  Future<void> startLocalServerForeground(String title, String detail) =>
      _desktop
      ? Future<void>.value()
      : _channel.invokeMethod<void>('startLocalServerForeground', {
          'title': title,
          'detail': detail,
        });

  Future<void> stopLocalServerForeground() => _desktop
      ? Future<void>.value()
      : _channel.invokeMethod<void>('stopLocalServerForeground');
}

class TrafficConnection {
  const TrafficConnection({
    required this.protocol,
    required this.ipVersion,
    required this.localAddress,
    required this.localPort,
    required this.remoteAddress,
    required this.remotePort,
    required this.state,
    required this.applicationProtocol,
    this.uid,
    this.processId,
    this.processName,
    this.packageName,
    this.applicationLabel,
    this.executablePath,
  });

  final String protocol;
  final int ipVersion;
  final String localAddress;
  final int localPort;
  final String remoteAddress;
  final int remotePort;
  final String state;
  final String applicationProtocol;
  final int? uid;
  final int? processId;
  final String? processName;
  final String? packageName;
  final String? applicationLabel;
  final String? executablePath;

  factory TrafficConnection.fromMap(Map<Object?, Object?> map) =>
      TrafficConnection(
        protocol: map['protocol'] as String? ?? 'Unknown',
        ipVersion: map['ipVersion'] as int? ?? 0,
        localAddress: map['localAddress'] as String? ?? '',
        localPort: map['localPort'] as int? ?? 0,
        remoteAddress: map['remoteAddress'] as String? ?? '',
        remotePort: map['remotePort'] as int? ?? 0,
        state: map['state'] as String? ?? 'Unknown',
        applicationProtocol: map['applicationProtocol'] as String? ?? 'Unknown',
        uid: map['uid'] as int?,
        processId: (map['pid'] as num?)?.toInt(),
        processName: map['processName'] as String?,
        packageName: map['packageName'] as String?,
        applicationLabel: map['applicationLabel'] as String?,
        executablePath: map['executablePath'] as String?,
      );
}

class AppTrafficUsage {
  const AppTrafficUsage({
    required this.uid,
    required this.label,
    required this.rxBytes,
    required this.txBytes,
    this.packageName,
    this.iconBytes,
    this.packageNames = const [],
    this.connectionCount = 0,
    this.confidence = 'bytes',
    this.executablePath,
  });
  final int uid;
  final String label;
  final String? packageName;
  final Uint8List? iconBytes;
  final List<String> packageNames;
  final int rxBytes;
  final int txBytes;
  final int connectionCount;
  final String confidence;
  final String? executablePath;
  int get totalBytes => rxBytes + txBytes;

  factory AppTrafficUsage.fromMap(Map<Object?, Object?> map) => AppTrafficUsage(
    uid: (map['uid'] as num?)?.toInt() ?? -1,
    label: map['label'] as String? ?? '未知应用',
    packageName: map['packageName'] as String?,
    iconBytes: map['iconBytes'] is Uint8List
        ? map['iconBytes'] as Uint8List
        : map['iconBytes'] is List<int>
        ? Uint8List.fromList(map['iconBytes'] as List<int>)
        : null,
    packageNames: (map['packageNames'] as List<Object?>? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false),
    rxBytes: (map['rxBytes'] as num?)?.toInt() ?? 0,
    txBytes: (map['txBytes'] as num?)?.toInt() ?? 0,
    connectionCount: (map['connectionCount'] as num?)?.toInt() ?? 0,
    confidence: map['confidence'] as String? ?? 'bytes',
    executablePath: map['executablePath'] as String?,
  );
}

class TrafficSnapshot {
  const TrafficSnapshot({
    required this.timestamp,
    required this.elapsedRealtimeMs,
    required this.totalRxBytes,
    required this.totalTxBytes,
    required this.mobileRxBytes,
    required this.mobileTxBytes,
    required this.appRxBytes,
    required this.appTxBytes,
    required this.connections,
    required this.connectionVisibility,
    required this.visibilityDetail,
  });

  final DateTime timestamp;
  final int elapsedRealtimeMs;
  final int? totalRxBytes;
  final int? totalTxBytes;
  final int? mobileRxBytes;
  final int? mobileTxBytes;
  final int? appRxBytes;
  final int? appTxBytes;
  final List<TrafficConnection> connections;
  final String connectionVisibility;
  final String visibilityDetail;

  factory TrafficSnapshot.fromMap(Map<Object?, Object?> map) => TrafficSnapshot(
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      (map['timestampMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    ),
    elapsedRealtimeMs: (map['elapsedRealtimeMs'] as num?)?.toInt() ?? 0,
    totalRxBytes: (map['totalRxBytes'] as num?)?.toInt(),
    totalTxBytes: (map['totalTxBytes'] as num?)?.toInt(),
    mobileRxBytes: (map['mobileRxBytes'] as num?)?.toInt(),
    mobileTxBytes: (map['mobileTxBytes'] as num?)?.toInt(),
    appRxBytes: (map['appRxBytes'] as num?)?.toInt(),
    appTxBytes: (map['appTxBytes'] as num?)?.toInt(),
    connections: (map['connections'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(TrafficConnection.fromMap)
        .toList(growable: false),
    connectionVisibility:
        map['connectionVisibility'] as String? ?? 'restricted',
    visibilityDetail: map['visibilityDetail'] as String? ?? '',
  );
}

class TrafficRateSample {
  const TrafficRateSample({
    required this.timestamp,
    required this.downloadBytesPerSecond,
    required this.uploadBytesPerSecond,
    required this.activeConnections,
  });
  final DateTime timestamp;
  final double downloadBytesPerSecond;
  final double uploadBytesPerSecond;
  final int activeConnections;
}

class PathMtuAttempt {
  const PathMtuAttempt({
    required this.mtu,
    required this.payload,
    required this.success,
    required this.elapsedMs,
    required this.output,
  });

  final int mtu;
  final int payload;
  final bool success;
  final double elapsedMs;
  final String output;

  factory PathMtuAttempt.fromMap(Map<Object?, Object?> map) => PathMtuAttempt(
    mtu: map['mtu'] as int? ?? 0,
    payload: map['payload'] as int? ?? 0,
    success: map['success'] as bool? ?? false,
    elapsedMs: (map['elapsedMs'] as num?)?.toDouble() ?? 0,
    output: map['output'] as String? ?? '',
  );
}

class PathMtuResult {
  const PathMtuResult({
    required this.host,
    required this.ipv6,
    required this.interfaceMtu,
    required this.pathMtu,
    required this.attempts,
    required this.conclusive,
  });

  final String host;
  final bool ipv6;
  final int interfaceMtu;
  final int? pathMtu;
  final List<PathMtuAttempt> attempts;
  final bool conclusive;

  factory PathMtuResult.fromMap(Map<Object?, Object?> map) => PathMtuResult(
    host: map['host'] as String? ?? '',
    ipv6: map['ipv6'] as bool? ?? false,
    interfaceMtu: map['interfaceMtu'] as int? ?? 0,
    pathMtu: map['pathMtu'] as int?,
    attempts: (map['attempts'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(PathMtuAttempt.fromMap)
        .toList(growable: false),
    conclusive: map['conclusive'] as bool? ?? false,
  );
}

class IperfNativeResult {
  const IperfNativeResult({
    required this.ok,
    required this.exitCode,
    required this.output,
  });

  final bool ok;
  final int exitCode;
  final String output;
}

class NativeCommandResult {
  const NativeCommandResult({
    required this.exitCode,
    required this.output,
    required this.command,
  });

  final int exitCode;
  final String output;
  final String command;
}

class NativeTraceHop {
  const NativeTraceHop({
    required this.hop,
    required this.elapsedMs,
    required this.reached,
    required this.timeout,
    required this.raw,
    this.address,
    this.hostname,
    this.samplesMs = const [],
  });

  final int hop;
  final String? address;
  final String? hostname;
  final double elapsedMs;
  final List<double?> samplesMs;
  final bool reached;
  final bool timeout;
  final String raw;

  factory NativeTraceHop.fromMap(Map<Object?, Object?> map) => NativeTraceHop(
    hop: map['hop'] as int? ?? 0,
    address: map['address'] as String?,
    hostname: map['hostname'] as String?,
    elapsedMs: (map['elapsedMs'] as num?)?.toDouble() ?? 0,
    samplesMs: (map['samplesMs'] as List<Object?>? ?? const [])
        .map((value) => (value as num?)?.toDouble())
        .toList(growable: false),
    reached: map['reached'] as bool? ?? false,
    timeout: map['timeout'] as bool? ?? false,
    raw: map['raw'] as String? ?? '',
  );
}
