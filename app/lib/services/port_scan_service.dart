import 'dart:async';
import 'dart:io';

enum PortState { open, closed }

class PortScanResult {
  const PortScanResult({
    required this.port,
    required this.state,
    required this.elapsed,
  });

  final int port;
  final PortState state;
  final Duration elapsed;
}

class PortScanService {
  static const maxPorts = 256;

  List<int> parsePorts(String input) {
    final ports = <int>{};
    for (final segment in input.split(',')) {
      final value = segment.trim();
      if (value.isEmpty) continue;
      if (value.contains('-')) {
        final range = value.split('-');
        if (range.length != 2) throw const FormatException('端口范围格式错误');
        final start = int.tryParse(range[0].trim());
        final end = int.tryParse(range[1].trim());
        if (start == null || end == null || start > end) {
          throw const FormatException('端口范围格式错误');
        }
        for (var port = start; port <= end; port++) {
          _validatePort(port);
          ports.add(port);
          if (ports.length > maxPorts) {
            throw const FormatException('一次最多扫描 256 个端口');
          }
        }
      } else {
        final port = int.tryParse(value);
        if (port == null) throw FormatException('无法识别端口：$value');
        _validatePort(port);
        ports.add(port);
      }
    }
    if (ports.isEmpty) throw const FormatException('请输入至少一个端口');
    final result = ports.toList()..sort();
    return result;
  }

  Stream<PortScanResult> scan({
    required String host,
    required List<int> ports,
    required Duration timeout,
    required CancellationToken token,
  }) async* {
    const batchSize = 20;
    for (var offset = 0; offset < ports.length; offset += batchSize) {
      if (token.isCancelled) return;
      final batch = ports.skip(offset).take(batchSize);
      final results = await Future.wait(
        batch.map((port) => _probe(host, port, timeout)),
      );
      for (final result in results) {
        if (token.isCancelled) return;
        yield result;
      }
    }
  }

  Future<PortScanResult> _probe(String host, int port, Duration timeout) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      stopwatch.stop();
      return PortScanResult(
        port: port,
        state: PortState.open,
        elapsed: stopwatch.elapsed,
      );
    } on Object {
      stopwatch.stop();
      return PortScanResult(
        port: port,
        state: PortState.closed,
        elapsed: stopwatch.elapsed,
      );
    } finally {
      socket?.destroy();
    }
  }

  void _validatePort(int port) {
    if (port < 1 || port > 65535) {
      throw FormatException('端口必须在 1～65535：$port');
    }
  }
}

class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
