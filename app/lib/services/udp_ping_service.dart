import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum UdpPingMode { echo, probe }

enum UdpProbeState { reply, refused, unreachable, unknown }

class UdpPingResult {
  const UdpPingResult({
    required this.state,
    required this.elapsed,
    required this.sentBytes,
    this.receivedBytes = 0,
    this.reply,
  });

  final UdpProbeState state;
  final Duration elapsed;
  final int sentBytes;
  final int receivedBytes;
  final String? reply;
}

class UdpPingService {
  Future<UdpPingResult> run({
    required String host,
    required int port,
    required UdpPingMode mode,
    String payload = 'ProtoDeck UDP Echo',
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (port < 1 || port > 65535) throw const FormatException('端口必须为 1～65535');
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) throw SocketException('无法解析目标 $host');
    final target = addresses.first;
    final socket = await RawDatagramSocket.bind(
      target.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    final bytes = utf8.encode(payload);
    final watch = Stopwatch()..start();
    try {
      socket.send(bytes, target, port);
      final completer = Completer<Datagram?>();
      late StreamSubscription<RawSocketEvent> subscription;
      subscription = socket.listen(
        (event) {
          if (event == RawSocketEvent.read && !completer.isCompleted) {
            completer.complete(socket.receive());
          }
        },
        onError: (Object error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      );
      try {
        final datagram = await completer.future.timeout(timeout);
        watch.stop();
        if (datagram == null) {
          return UdpPingResult(
            state: UdpProbeState.unknown,
            elapsed: watch.elapsed,
            sentBytes: bytes.length,
          );
        }
        final reply = utf8.decode(datagram.data, allowMalformed: true);
        return UdpPingResult(
          state: UdpProbeState.reply,
          elapsed: watch.elapsed,
          sentBytes: bytes.length,
          receivedBytes: datagram.data.length,
          reply: reply,
        );
      } on TimeoutException {
        watch.stop();
        return UdpPingResult(
          state: UdpProbeState.unknown,
          elapsed: watch.elapsed,
          sentBytes: bytes.length,
          reply: mode == UdpPingMode.echo ? '未收到 Echo 回包' : '静默，端口状态未知',
        );
      } on SocketException catch (error) {
        watch.stop();
        final message = error.message.toLowerCase();
        return UdpPingResult(
          state: message.contains('refused')
              ? UdpProbeState.refused
              : UdpProbeState.unreachable,
          elapsed: watch.elapsed,
          sentBytes: bytes.length,
          reply: error.message,
        );
      } finally {
        await subscription.cancel();
      }
    } finally {
      socket.close();
    }
  }
}
