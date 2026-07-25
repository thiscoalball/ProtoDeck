import 'dart:async';
import 'dart:io';

class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class PingSample {
  const PingSample({
    required this.sequence,
    required this.elapsed,
    required this.success,
    this.error,
  });

  final int sequence;
  final Duration elapsed;
  final bool success;
  final String? error;
}

class TcpPingService {
  Stream<PingSample> run({
    required String host,
    required int port,
    required int count,
    required Duration timeout,
    required CancellationToken token,
  }) async* {
    for (var sequence = 1; sequence <= count; sequence++) {
      if (token.isCancelled) return;
      final stopwatch = Stopwatch()..start();
      Socket? socket;
      try {
        socket = await Socket.connect(host, port, timeout: timeout);
        stopwatch.stop();
        yield PingSample(
          sequence: sequence,
          elapsed: stopwatch.elapsed,
          success: true,
        );
      } on Object catch (error) {
        stopwatch.stop();
        yield PingSample(
          sequence: sequence,
          elapsed: stopwatch.elapsed,
          success: false,
          error: _friendlyError(error),
        );
      } finally {
        socket?.destroy();
      }
      if (sequence < count && !token.isCancelled) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  String _friendlyError(Object error) {
    if (error is SocketException) {
      return error.osError?.message ?? error.message;
    }
    if (error is TimeoutException) return '连接超时';
    return error.toString();
  }
}
