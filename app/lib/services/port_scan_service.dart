import 'dart:async';
import 'dart:io';

enum PortState { open, closed, filtered, unreachable, error }

class PortScanResult {
  const PortScanResult({
    required this.port,
    required this.state,
    required this.elapsed,
    required this.address,
    this.banner,
    this.error,
  });

  final int port;
  final PortState state;
  final Duration elapsed;
  final String address;
  final String? banner;
  final String? error;
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
    int concurrency = 20,
    bool grabBanner = false,
    InternetAddressType? addressType,
  }) async* {
    if (concurrency < 1 || concurrency > 100) {
      throw const FormatException('端口扫描并发必须为 1～100');
    }
    final resolved = await InternetAddress.lookup(
      host,
      type: addressType ?? InternetAddressType.any,
    );
    if (resolved.isEmpty) throw SocketException('Target did not resolve');
    final target = resolved.first;
    for (var offset = 0; offset < ports.length; offset += concurrency) {
      if (token.isCancelled) return;
      final batch = ports.skip(offset).take(concurrency);
      final results = await Future.wait(
        batch.map(
          (port) => _probe(target, host, port, timeout, grabBanner: grabBanner),
        ),
      );
      for (final result in results) {
        if (token.isCancelled) return;
        yield result;
      }
    }
  }

  Future<PortScanResult> _probe(
    InternetAddress address,
    String host,
    int port,
    Duration timeout, {
    required bool grabBanner,
  }) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
      final banner = grabBanner
          ? await _readBanner(socket, host, port, timeout)
          : null;
      stopwatch.stop();
      return PortScanResult(
        port: port,
        state: PortState.open,
        elapsed: stopwatch.elapsed,
        address: address.address,
        banner: banner,
      );
    } on TimeoutException catch (error) {
      stopwatch.stop();
      return PortScanResult(
        port: port,
        state: PortState.filtered,
        elapsed: stopwatch.elapsed,
        address: address.address,
        error: error.toString(),
      );
    } on SocketException catch (error) {
      stopwatch.stop();
      return PortScanResult(
        port: port,
        state: _socketState(error),
        elapsed: stopwatch.elapsed,
        address: address.address,
        error: error.message,
      );
    } on Object catch (error) {
      stopwatch.stop();
      return PortScanResult(
        port: port,
        state: PortState.error,
        elapsed: stopwatch.elapsed,
        address: address.address,
        error: error.toString(),
      );
    } finally {
      socket?.destroy();
    }
  }

  Future<String?> _readBanner(
    Socket socket,
    String host,
    int port,
    Duration connectTimeout,
  ) async {
    const httpPorts = {80, 3000, 5000, 8000, 8008, 8080, 8081, 8888};
    if (httpPorts.contains(port)) {
      socket.write(
        'HEAD / HTTP/1.0\r\nHost: $host\r\nConnection: close\r\n\r\n',
      );
      await socket.flush();
    }
    final bannerTimeout = Duration(
      milliseconds: connectTimeout.inMilliseconds.clamp(250, 900),
    );
    try {
      final bytes = await socket.first.timeout(bannerTimeout);
      if (bytes.isEmpty) return null;
      final text = String.fromCharCodes(
        bytes.take(768),
      ).replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '.').trim();
      return text.isEmpty ? null : text;
    } on TimeoutException {
      return null;
    }
  }

  PortState _socketState(SocketException error) {
    final code = error.osError?.errorCode;
    if (const {61, 111, 10061}.contains(code)) return PortState.closed;
    if (const {51, 65, 101, 113, 10051, 10065}.contains(code)) {
      return PortState.unreachable;
    }
    if (const {60, 110, 10060}.contains(code)) return PortState.filtered;
    final message = error.message.toLowerCase();
    if (message.contains('refused')) return PortState.closed;
    if (message.contains('unreachable')) return PortState.unreachable;
    if (message.contains('timed out')) return PortState.filtered;
    return PortState.error;
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
