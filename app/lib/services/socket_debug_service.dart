import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum SocketDebugProtocol { tcp, udp }

enum SocketDebugRole { client, server }

class SocketDebugEvent {
  const SocketDebugEvent({
    required this.time,
    required this.direction,
    required this.peer,
    required this.bytes,
    this.message,
  });

  final DateTime time;
  final String direction;
  final String peer;
  final Uint8List bytes;
  final String? message;

  String get text => message ?? utf8.decode(bytes, allowMalformed: true);
  String get hex => bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join(' ')
      .toUpperCase();
}

class SocketDebugService {
  final _events = StreamController<SocketDebugEvent>.broadcast();
  final _tcpPeers = <Socket>[];
  ServerSocket? _tcpServer;
  Socket? _tcpClient;
  RawDatagramSocket? _udp;
  InternetAddress? _udpTarget;
  int? _udpTargetPort;

  Stream<SocketDebugEvent> get events => _events.stream;
  bool get running => _tcpServer != null || _tcpClient != null || _udp != null;
  int get peerCount => _tcpPeers.length + (_tcpClient == null ? 0 : 1);

  Future<String> start({
    required SocketDebugProtocol protocol,
    required SocketDebugRole role,
    required String host,
    required int port,
    String bindAddress = '0.0.0.0',
    int localPort = 0,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await stop();
    if (port < 1 || port > 65535) {
      throw const FormatException('端口必须为 1～65535');
    }
    if (protocol == SocketDebugProtocol.tcp) {
      if (role == SocketDebugRole.server) {
        _tcpServer = await ServerSocket.bind(bindAddress, port, shared: true);
        _tcpServer!.listen(_acceptTcp, onError: _emitError);
        return 'TCP Server ${_tcpServer!.address.address}:${_tcpServer!.port}';
      }
      final socket = await Socket.connect(
        host.trim(),
        port,
        sourceAddress: bindAddress == '0.0.0.0' ? null : bindAddress,
        sourcePort: localPort,
        timeout: timeout,
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      _tcpClient = socket;
      _listenTcp(socket, client: true);
      return 'TCP Client ${socket.address.address}:${socket.port}';
    }

    final bindPort = role == SocketDebugRole.server ? port : localPort;
    _udp = await RawDatagramSocket.bind(bindAddress, bindPort);
    if (role == SocketDebugRole.client) {
      final addresses = await InternetAddress.lookup(host.trim());
      if (addresses.isEmpty) throw StateError('无法解析目标地址');
      _udpTarget = addresses.first;
      _udpTargetPort = port;
    }
    _udp!.listen(_onUdp, onError: _emitError);
    return 'UDP ${role == SocketDebugRole.server ? 'Server' : 'Client'} '
        '${_udp!.address.address}:${_udp!.port}';
  }

  Future<void> send(
    Uint8List bytes, {
    String? host,
    int? port,
    bool broadcast = false,
  }) async {
    if (bytes.isEmpty) throw const FormatException('发送内容不能为空');
    if (_tcpClient != null) {
      _tcpClient!.add(bytes);
      await _tcpClient!.flush();
      _emit('TX', _tcpPeer(_tcpClient!), bytes);
      return;
    }
    if (_tcpServer != null) {
      if (_tcpPeers.isEmpty) throw StateError('尚无 TCP 客户端连接');
      for (final peer in List<Socket>.from(_tcpPeers)) {
        peer.add(bytes);
        await peer.flush();
        _emit('TX', _tcpPeer(peer), bytes);
      }
      return;
    }
    final udp = _udp;
    if (udp == null) throw StateError('请先启动调试会话');
    InternetAddress? address = _udpTarget;
    var targetPort = _udpTargetPort;
    if (host?.trim().isNotEmpty == true) {
      address = (await InternetAddress.lookup(host!.trim())).first;
    }
    if (port != null) targetPort = port;
    if (address == null || targetPort == null) {
      throw const FormatException('UDP Server 回复前请填写目标地址和端口');
    }
    udp.broadcastEnabled = broadcast;
    final sent = udp.send(bytes, address, targetPort);
    if (sent <= 0) throw StateError('UDP 数据未发送');
    _emit('TX', '${address.address}:$targetPort', bytes);
  }

  void _acceptTcp(Socket socket) {
    _tcpPeers.add(socket);
    _emit('SYS', _tcpPeer(socket), Uint8List(0), '客户端已连接');
    _listenTcp(socket, client: false);
  }

  void _listenTcp(Socket socket, {required bool client}) {
    socket.listen(
      (data) => _emit('RX', _tcpPeer(socket), Uint8List.fromList(data)),
      onError: _emitError,
      onDone: () {
        _tcpPeers.remove(socket);
        if (client && identical(_tcpClient, socket)) _tcpClient = null;
        _emit('SYS', _tcpPeer(socket), Uint8List(0), '连接已关闭');
        socket.destroy();
      },
      cancelOnError: true,
    );
  }

  void _onUdp(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    Datagram? packet;
    while ((packet = _udp?.receive()) != null) {
      final value = packet!;
      _udpTarget ??= value.address;
      _udpTargetPort ??= value.port;
      _emit(
        'RX',
        '${value.address.address}:${value.port}',
        Uint8List.fromList(value.data),
      );
    }
  }

  void _emit(String direction, String peer, Uint8List bytes, [String? text]) {
    if (_events.isClosed) return;
    _events.add(
      SocketDebugEvent(
        time: DateTime.now(),
        direction: direction,
        peer: peer,
        bytes: bytes,
        message: text,
      ),
    );
  }

  void _emitError(Object error) =>
      _emit('ERR', '', Uint8List(0), error.toString());

  String _tcpPeer(Socket socket) =>
      '${socket.remoteAddress.address}:${socket.remotePort}';

  Future<void> stop() async {
    await _tcpServer?.close();
    _tcpServer = null;
    _tcpClient?.destroy();
    _tcpClient = null;
    for (final peer in List<Socket>.from(_tcpPeers)) {
      peer.destroy();
    }
    _tcpPeers.clear();
    _udp?.close();
    _udp = null;
    _udpTarget = null;
    _udpTargetPort = null;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  static Uint8List parsePayload(String input, {required bool hex}) {
    if (!hex) return Uint8List.fromList(utf8.encode(input));
    final normalized = input.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (normalized.length.isOdd) {
      throw const FormatException('Hex 数据必须包含完整字节');
    }
    if (normalized.isEmpty) return Uint8List(0);
    return Uint8List.fromList([
      for (var index = 0; index < normalized.length; index += 2)
        int.parse(normalized.substring(index, index + 2), radix: 16),
    ]);
  }
}
