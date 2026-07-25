import 'dart:io';
import 'dart:typed_data';

class WakeOnLanService {
  Future<int> send({
    required String mac,
    String broadcast = '255.255.255.255',
    int port = 9,
    int repeat = 3,
  }) async {
    final normalized = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (normalized.length != 12 ||
        !RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(normalized)) {
      throw const FormatException('MAC 地址格式无效');
    }
    if (port < 1 || port > 65535) throw const FormatException('端口范围应为 1～65535');
    if (repeat < 1 || repeat > 10) throw const FormatException('发送次数范围应为 1～10');
    final address = InternetAddress.tryParse(broadcast);
    if (address == null || address.type != InternetAddressType.IPv4) {
      throw const FormatException('广播地址必须是 IPv4 地址');
    }
    final macBytes = Uint8List.fromList([
      for (var i = 0; i < 12; i += 2)
        int.parse(normalized.substring(i, i + 2), radix: 16),
    ]);
    final packet = BytesBuilder()..add(List<int>.filled(6, 0xff));
    for (var i = 0; i < 16; i++) packet.add(macBytes);
    final bytes = packet.takeBytes();
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    var sent = 0;
    try {
      for (var i = 0; i < repeat; i++) {
        sent += socket.send(bytes, address, port) > 0 ? 1 : 0;
        if (i + 1 < repeat)
          await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    } finally {
      socket.close();
    }
    return sent;
  }
}
