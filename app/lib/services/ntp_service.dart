import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class NtpResult {
  const NtpResult({
    required this.server,
    required this.address,
    required this.queriedAt,
    required this.serverTime,
    required this.offsetMs,
    required this.roundTripMs,
    required this.stratum,
    required this.leapIndicator,
    required this.version,
    required this.mode,
    required this.referenceId,
    required this.referenceTime,
    required this.rootDelayMs,
    required this.rootDispersionMs,
    required this.precisionSeconds,
  });

  final String server;
  final String address;
  final DateTime queriedAt;
  final DateTime serverTime;
  final double offsetMs;
  final double roundTripMs;
  final int stratum;
  final int leapIndicator;
  final int version;
  final int mode;
  final String referenceId;
  final DateTime? referenceTime;
  final double rootDelayMs;
  final double rootDispersionMs;
  final double precisionSeconds;
}

class NtpService {
  RawDatagramSocket? _socket;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _socket?.close();
    _socket = null;
  }

  Future<NtpResult> query(
    String server, {
    int port = 123,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    _cancelled = false;
    final host = server.trim();
    if (host.isEmpty) throw const FormatException('NTP 服务器不能为空');
    final addresses = await InternetAddress.lookup(host).timeout(timeout);
    if (addresses.isEmpty) throw SocketException('无法解析 $host');
    final address = addresses.first;
    final socket = await RawDatagramSocket.bind(
      address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    _socket = socket;
    try {
      final packet = Uint8List(48);
      packet[0] = 0x23; // LI=0, VN=4, Mode=3 (client).
      final t1 = DateTime.now().toUtc();
      final sentStamp = _writeTimestamp(packet, 40, t1);
      if (socket.send(packet, address, port) != packet.length) {
        throw SocketException('NTP 请求发送不完整');
      }
      final completer = Completer<(Datagram, DateTime)>();
      late StreamSubscription<RawSocketEvent> subscription;
      subscription = socket.listen(
        (event) {
          if (event != RawSocketEvent.read || completer.isCompleted) return;
          final datagram = socket.receive();
          if (datagram != null) {
            completer.complete((datagram, DateTime.now().toUtc()));
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
      );
      final received = await completer.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException('NTP 查询超时', timeout),
      );
      await subscription.cancel();
      if (_cancelled) throw const NtpCancelled();
      final response = received.$1.data;
      final t4 = received.$2;
      if (response.length < 48) throw const FormatException('NTP 响应不足 48 字节');
      final data = ByteData.sublistView(response);
      final first = response[0];
      final leap = first >> 6;
      final version = (first >> 3) & 0x07;
      final mode = first & 0x07;
      if (mode != 4 && mode != 5)
        throw FormatException('NTP 响应 Mode=$mode，不是服务器响应');
      final stratum = response[1];
      if (stratum == 0) {
        final code = String.fromCharCodes(response.sublist(12, 16));
        throw StateError('NTP 服务器拒绝请求（Kiss-o\'-Death: $code）');
      }
      final originSeconds = data.getUint32(24, Endian.big);
      final originFraction = data.getUint32(28, Endian.big);
      if (originSeconds != sentStamp.$1 || originFraction != sentStamp.$2) {
        throw const FormatException('NTP Origin Timestamp 与本次请求不匹配');
      }
      final t2 = _readTimestamp(data, 32);
      final t3 = _readTimestamp(data, 40);
      final offsetMicros =
          (t2.difference(t1).inMicroseconds +
              t3.difference(t4).inMicroseconds) /
          2;
      final delayMicros =
          t4.difference(t1).inMicroseconds - t3.difference(t2).inMicroseconds;
      final precisionPower = data.getInt8(3);
      return NtpResult(
        server: host,
        address: received.$1.address.address,
        queriedAt: t4,
        serverTime: t3,
        offsetMs: offsetMicros / 1000,
        roundTripMs: delayMicros.clamp(0, 1 << 53) / 1000,
        stratum: stratum,
        leapIndicator: leap,
        version: version,
        mode: mode,
        referenceId: _referenceId(response.sublist(12, 16), stratum),
        referenceTime: _readOptionalTimestamp(data, 16),
        rootDelayMs: data.getInt32(4, Endian.big) / 65536 * 1000,
        rootDispersionMs: data.getUint32(8, Endian.big) / 65536 * 1000,
        precisionSeconds: _powerOfTwo(precisionPower),
      );
    } finally {
      socket.close();
      if (identical(_socket, socket)) _socket = null;
    }
  }
}

class NtpCancelled implements Exception {
  const NtpCancelled();
  @override
  String toString() => 'NTP 查询已停止';
}

const _ntpEpochOffset = 2208988800;

(int, int) _writeTimestamp(Uint8List target, int offset, DateTime time) {
  final micros = time.microsecondsSinceEpoch;
  final seconds = micros ~/ 1000000 + _ntpEpochOffset;
  final remainingMicros = micros.remainder(1000000);
  final fraction = ((remainingMicros * 0x100000000) ~/ 1000000);
  final data = ByteData.sublistView(target);
  data.setUint32(offset, seconds, Endian.big);
  data.setUint32(offset + 4, fraction, Endian.big);
  return (seconds, fraction);
}

DateTime _readTimestamp(ByteData data, int offset) {
  final seconds = data.getUint32(offset, Endian.big);
  final fraction = data.getUint32(offset + 4, Endian.big);
  final unixSeconds = seconds - _ntpEpochOffset;
  final micros = (fraction * 1000000) ~/ 0x100000000;
  return DateTime.fromMicrosecondsSinceEpoch(
    unixSeconds * 1000000 + micros,
    isUtc: true,
  );
}

DateTime? _readOptionalTimestamp(ByteData data, int offset) {
  if (data.getUint32(offset, Endian.big) == 0 &&
      data.getUint32(offset + 4, Endian.big) == 0) {
    return null;
  }
  return _readTimestamp(data, offset);
}

String _referenceId(Uint8List bytes, int stratum) {
  if (stratum <= 1 && bytes.every((value) => value >= 32 && value <= 126)) {
    return String.fromCharCodes(bytes);
  }
  return bytes.join('.');
}

double _powerOfTwo(int exponent) {
  if (exponent == 0) return 1;
  var value = 1.0;
  if (exponent > 0) {
    for (var i = 0; i < exponent; i++) value *= 2;
  } else {
    for (var i = 0; i > exponent; i--) value /= 2;
  }
  return value;
}
