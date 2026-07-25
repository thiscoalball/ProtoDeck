import 'dart:io';

import 'ip_tools_service.dart';

class LanDevice {
  const LanDevice({
    required this.address,
    required this.openPorts,
    required this.elapsed,
    this.hostname,
  });

  final String address;
  final String? hostname;
  final List<int> openPorts;
  final Duration elapsed;
}

class LanScanProgress {
  const LanScanProgress({
    required this.completed,
    required this.total,
    required this.devices,
    required this.running,
  });

  final int completed;
  final int total;
  final List<LanDevice> devices;
  final bool running;
}

class LanScanCancellationToken {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class LanScanService {
  static const defaultPorts = [22, 23, 53, 80, 443, 445, 5201, 8080];
  final _ipTools = IpToolsService();

  Stream<LanScanProgress> scan(
    String cidr, {
    List<int> ports = defaultPorts,
    int concurrency = 24,
    Duration timeout = const Duration(milliseconds: 450),
    LanScanCancellationToken? token,
  }) async* {
    final parts = cidr.trim().split('/');
    if (parts.length != 2) throw const FormatException('请输入 IPv4 CIDR');
    final ip = _ipTools.parseIpv4(parts[0]);
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 20 || prefix > 32) {
      throw const FormatException('局域网扫描范围必须为 /20～/32');
    }
    final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    final network = ip & mask;
    final broadcast = network | (~mask & 0xFFFFFFFF);
    final first = prefix >= 31 ? network : network + 1;
    final last = prefix >= 31 ? broadcast : broadcast - 1;
    final addresses = [
      for (var value = first; value <= last; value++)
        _ipTools.formatIpv4(value),
    ];
    final cancellation = token ?? LanScanCancellationToken();
    final devices = <LanDevice>[];
    var completed = 0;
    yield LanScanProgress(
      completed: 0,
      total: addresses.length,
      devices: const [],
      running: true,
    );
    for (
      var offset = 0;
      offset < addresses.length && !cancellation.cancelled;
      offset += concurrency
    ) {
      final end = (offset + concurrency).clamp(0, addresses.length);
      final batch = addresses.sublist(offset, end);
      final found = await Future.wait(
        batch.map((address) => _probe(address, ports, timeout)),
      );
      devices.addAll(found.whereType<LanDevice>());
      completed += batch.length;
      yield LanScanProgress(
        completed: completed,
        total: addresses.length,
        devices: List.unmodifiable(
          devices..sort(
            (a, b) => _ipTools
                .parseIpv4(a.address)
                .compareTo(_ipTools.parseIpv4(b.address)),
          ),
        ),
        running: !cancellation.cancelled && completed < addresses.length,
      );
    }
    if (cancellation.cancelled) {
      yield LanScanProgress(
        completed: completed,
        total: addresses.length,
        devices: List.unmodifiable(devices),
        running: false,
      );
    }
  }

  Future<LanDevice?> _probe(
    String address,
    List<int> ports,
    Duration timeout,
  ) async {
    final watch = Stopwatch()..start();
    final openPorts = <int>[];
    await Future.wait(
      ports.map((port) async {
        Socket? socket;
        try {
          socket = await Socket.connect(address, port, timeout: timeout);
          openPorts.add(port);
        } on Object {
          // Closed and filtered ports are both expected during discovery.
        } finally {
          socket?.destroy();
        }
      }),
    );
    watch.stop();
    if (openPorts.isEmpty) return null;
    String? hostname;
    try {
      final reverse = await InternetAddress(
        address,
      ).reverse().timeout(const Duration(milliseconds: 500));
      if (reverse.host != address) hostname = reverse.host;
    } on Object {
      // Reverse DNS is optional.
    }
    openPorts.sort();
    return LanDevice(
      address: address,
      hostname: hostname,
      openPorts: openPorts,
      elapsed: watch.elapsed,
    );
  }
}
