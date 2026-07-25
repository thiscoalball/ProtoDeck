import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/app_database.dart';

enum SshTunnelMode { local, remote, dynamic }

class SshTunnelConfig {
  const SshTunnelConfig({
    required this.mode,
    required this.bindHost,
    required this.bindPort,
    this.targetHost = '',
    this.targetPort = 0,
  });
  final SshTunnelMode mode;
  final String bindHost;
  final int bindPort;
  final String targetHost;
  final int targetPort;
}

class SshTunnelStats {
  const SshTunnelStats({
    required this.running,
    required this.listenHost,
    required this.listenPort,
    required this.activeConnections,
    required this.uploadBytes,
    required this.downloadBytes,
    this.error,
  });
  final bool running;
  final String listenHost;
  final int listenPort;
  final int activeConnections;
  final int uploadBytes;
  final int downloadBytes;
  final String? error;
}

class SshTunnelService {
  SshTunnelService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  final _stats = StreamController<SshTunnelStats>.broadcast();
  SSHClient? _client;
  ServerSocket? _localServer;
  SSHRemoteForward? _remoteForward;
  SSHDynamicForward? _dynamicForward;
  final _sockets = <Socket>{};
  var _active = 0;
  var _upload = 0;
  var _download = 0;
  var _host = '';
  var _port = 0;
  bool _running = false;

  Stream<SshTunnelStats> get stats => _stats.stream;
  bool get running => _running;

  Future<void> start(
    RemoteProfile profile,
    SshTunnelConfig config, {
    required Future<bool> Function(String algorithm, String fingerprint)
    verifyHostKey,
  }) async {
    if (_running) throw StateError('已有 SSH 隧道正在运行');
    if (config.bindPort < 0 || config.bindPort > 65535) {
      throw const FormatException('监听端口必须是 0～65535');
    }
    if (config.mode != SshTunnelMode.dynamic &&
        (config.targetHost.trim().isEmpty ||
            config.targetPort < 1 ||
            config.targetPort > 65535)) {
      throw const FormatException('请输入有效的目标主机和端口');
    }
    final secret = profile.secretRef == null
        ? null
        : await _storage.read(key: profile.secretRef!);
    final credentials = _decodeSecret(secret);
    final identities = profile.authType == 'privateKey'
        ? SSHKeyPair.fromPem(
            credentials['privateKey'] ?? '',
            credentials['passphrase']?.isEmpty == true
                ? null
                : credentials['passphrase'],
          )
        : null;
    final socket = await SSHSocket.connect(
      profile.host,
      profile.port,
      timeout: const Duration(seconds: 10),
    );
    final client = SSHClient(
      socket,
      username: profile.username,
      onPasswordRequest: profile.authType == 'password'
          ? () => credentials['password'] ?? ''
          : null,
      identities: identities,
      onVerifyHostKey: (algorithm, fingerprint) =>
          verifyHostKey(algorithm, base64Encode(fingerprint)),
      keepAliveInterval: const Duration(seconds: 20),
    );
    try {
      await client.authenticated.timeout(const Duration(seconds: 15));
      _client = client;
      _running = true;
      _active = 0;
      _upload = 0;
      _download = 0;
      switch (config.mode) {
        case SshTunnelMode.local:
          final server = await ServerSocket.bind(
            config.bindHost,
            config.bindPort,
            shared: true,
          );
          _localServer = server;
          _host = server.address.address;
          _port = server.port;
          server.listen((socket) => _acceptLocal(client, socket, config));
        case SshTunnelMode.remote:
          final forward = await client.forwardRemote(
            host: config.bindHost,
            port: config.bindPort,
          );
          if (forward == null) throw StateError('SSH 服务端拒绝 Remote Forwarding');
          _remoteForward = forward;
          _host = forward.host;
          _port = forward.port;
          forward.connections.listen(
            (channel) => _acceptRemote(channel, config),
          );
        case SshTunnelMode.dynamic:
          final forward = await client.forwardDynamic(
            bindHost: config.bindHost,
            bindPort: config.bindPort,
            options: const SSHDynamicForwardOptions(
              handshakeTimeout: Duration(seconds: 10),
              connectTimeout: Duration(seconds: 15),
              maxConnections: 64,
            ),
          );
          _dynamicForward = forward;
          _host = forward.host;
          _port = forward.port;
      }
      _emit();
      client.done.whenComplete(() {
        if (_running) {
          _running = false;
          _emit(error: 'SSH 连接已断开');
        }
      });
    } on Object {
      client.close();
      _client = null;
      _running = false;
      rethrow;
    }
  }

  Future<void> _acceptLocal(
    SSHClient client,
    Socket socket,
    SshTunnelConfig config,
  ) async {
    _sockets.add(socket);
    _active++;
    _emit();
    try {
      final channel = await client.forwardLocal(
        config.targetHost,
        config.targetPort,
      );
      _bridge(socket, channel);
    } on Object catch (error) {
      socket.destroy();
      _sockets.remove(socket);
      _active = (_active - 1).clamp(0, 1 << 20);
      _emit(error: 'Local Forward 连接失败：$error');
    }
  }

  Future<void> _acceptRemote(
    SSHForwardChannel channel,
    SshTunnelConfig config,
  ) async {
    try {
      final socket = await Socket.connect(
        config.targetHost,
        config.targetPort,
        timeout: const Duration(seconds: 10),
      );
      _sockets.add(socket);
      _active++;
      _emit();
      _bridge(socket, channel, reversed: true);
    } on Object catch (error) {
      channel.destroy();
      _emit(error: 'Remote Forward 目标连接失败：$error');
    }
  }

  void _bridge(
    Socket socket,
    SSHForwardChannel channel, {
    bool reversed = false,
  }) {
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      socket.destroy();
      channel.destroy();
      _sockets.remove(socket);
      _active = (_active - 1).clamp(0, 1 << 20);
      _emit();
    }

    socket.listen(
      (data) {
        channel.sink.add(data);
        if (reversed) {
          _download += data.length;
        } else {
          _upload += data.length;
        }
        _emit();
      },
      onDone: close,
      onError: (_) => close(),
      cancelOnError: true,
    );
    channel.stream.listen(
      (data) {
        socket.add(data);
        if (reversed) {
          _upload += data.length;
        } else {
          _download += data.length;
        }
        _emit();
      },
      onDone: close,
      onError: (_) => close(),
      cancelOnError: true,
    );
  }

  Future<void> stop() async {
    _running = false;
    await _localServer?.close();
    _localServer = null;
    _remoteForward?.close();
    _remoteForward = null;
    await _dynamicForward?.close();
    _dynamicForward = null;
    for (final socket in _sockets.toList()) socket.destroy();
    _sockets.clear();
    _client?.close();
    _client = null;
    _active = 0;
    _emit();
  }

  Future<void> dispose() async {
    await stop();
    await _stats.close();
  }

  void _emit({String? error}) {
    if (_stats.isClosed) return;
    _stats.add(
      SshTunnelStats(
        running: _running,
        listenHost: _host,
        listenPort: _port,
        activeConnections: _active,
        uploadBytes: _upload,
        downloadBytes: _download,
        error: error,
      ),
    );
  }
}

Map<String, String> _decodeSecret(String? value) {
  if (value == null || value.isEmpty) return const {};
  try {
    final decoded = jsonDecode(value) as Map<String, Object?>;
    return decoded.map((key, value) => MapEntry(key, value?.toString() ?? ''));
  } on FormatException {
    return {'password': value};
  }
}
