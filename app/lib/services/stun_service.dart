import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class StunBindingResult {
  const StunBindingResult({
    required this.server,
    required this.serverAddress,
    required this.localAddress,
    required this.localPort,
    required this.mappedAddress,
    required this.mappedPort,
    required this.elapsed,
    required this.software,
  });

  final String server;
  final String serverAddress;
  final String localAddress;
  final int localPort;
  final String mappedAddress;
  final int mappedPort;
  final Duration elapsed;
  final String? software;
}

class StunService {
  static const _cookie = 0x2112A442;

  Future<StunBindingResult> binding({
    required String server,
    int port = 3478,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (server.trim().isEmpty) throw const FormatException('STUN 服务器不能为空');
    if (port < 1 || port > 65535) throw const FormatException('端口范围应为 1～65535');
    final addresses = await InternetAddress.lookup(
      server.trim(),
    ).timeout(timeout);
    final target = addresses.firstWhere(
      (item) => item.type == InternetAddressType.IPv4,
      orElse: () => addresses.first,
    );
    final socket = await RawDatagramSocket.bind(
      target.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    final transaction = Uint8List.fromList(
      List<int>.generate(12, (_) => Random.secure().nextInt(256)),
    );
    final request = Uint8List(20);
    final data = ByteData.sublistView(request);
    data.setUint16(0, 0x0001);
    data.setUint16(2, 0);
    data.setUint32(4, _cookie);
    request.setRange(8, 20, transaction);
    final watch = Stopwatch()..start();
    final completer = Completer<Datagram>();
    late StreamSubscription<RawSocketEvent> subscription;
    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read || completer.isCompleted) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final bytes = datagram!.data;
        if (bytes.length >= 20 && _matches(bytes, transaction)) {
          completer.complete(datagram);
          break;
        }
      }
    }, onError: completer.completeError);
    try {
      socket.send(request, target, port);
      final response = await completer.future.timeout(timeout);
      watch.stop();
      final parsed = _parse(response.data, transaction);
      return StunBindingResult(
        server: '$server:$port',
        serverAddress: response.address.address,
        localAddress: socket.address.address,
        localPort: socket.port,
        mappedAddress: parsed.$1,
        mappedPort: parsed.$2,
        elapsed: watch.elapsed,
        software: parsed.$3,
      );
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }

  bool _matches(Uint8List bytes, Uint8List transaction) {
    final data = ByteData.sublistView(bytes);
    if (data.getUint16(0) != 0x0101 || data.getUint32(4) != _cookie)
      return false;
    for (var i = 0; i < 12; i++) {
      if (bytes[8 + i] != transaction[i]) return false;
    }
    return true;
  }

  (String, int, String?) _parse(Uint8List bytes, Uint8List transaction) {
    final data = ByteData.sublistView(bytes);
    final end = min(bytes.length, 20 + data.getUint16(2));
    String? address;
    int? port;
    String? software;
    var offset = 20;
    while (offset + 4 <= end) {
      final type = data.getUint16(offset);
      final length = data.getUint16(offset + 2);
      final value = offset + 4;
      if (value + length > end) break;
      if ((type == 0x0020 || type == 0x0001) && length >= 8) {
        final family = bytes[value + 1];
        final xor = type == 0x0020;
        port = data.getUint16(value + 2) ^ (xor ? (_cookie >> 16) : 0);
        final count = family == 0x02 ? 16 : 4;
        if (length >= 4 + count) {
          final raw = Uint8List(count);
          final mask = Uint8List.fromList([
            0x21,
            0x12,
            0xA4,
            0x42,
            ...transaction,
          ]);
          for (var i = 0; i < count; i++)
            raw[i] = bytes[value + 4 + i] ^ (xor ? mask[i] : 0);
          address = InternetAddress.fromRawAddress(raw).address;
        }
      } else if (type == 0x8022) {
        software = String.fromCharCodes(bytes.sublist(value, value + length));
      }
      offset = value + ((length + 3) & ~3);
    }
    if (address == null || port == null)
      throw const FormatException('STUN 响应没有 MAPPED-ADDRESS');
    return (address, port, software);
  }
}
