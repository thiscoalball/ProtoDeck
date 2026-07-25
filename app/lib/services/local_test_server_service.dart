import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum LocalTestServerMode { http, tcpEcho }

enum LocalTestServerStatus { stopped, starting, listening, stopping, failed }

class LocalTestServerEvent {
  const LocalTestServerEvent({
    required this.time,
    required this.kind,
    required this.peer,
    required this.summary,
    this.detail,
  });

  final DateTime time;
  final String kind;
  final String peer;
  final String summary;
  final String? detail;
}

class LocalTestServerSnapshot {
  const LocalTestServerSnapshot({
    required this.status,
    required this.mode,
    required this.bindAddress,
    required this.port,
    required this.startedAt,
    required this.requestCount,
    required this.connectionCount,
    required this.activeConnections,
    required this.receivedBytes,
    required this.sentBytes,
    required this.events,
    this.error,
  });

  final LocalTestServerStatus status;
  final LocalTestServerMode mode;
  final String bindAddress;
  final int port;
  final DateTime? startedAt;
  final int requestCount;
  final int connectionCount;
  final int activeConnections;
  final int receivedBytes;
  final int sentBytes;
  final List<LocalTestServerEvent> events;
  final String? error;

  bool get running => status == LocalTestServerStatus.listening;
}

/// A process-local HTTP or TCP echo listener for quick connectivity checks.
/// The singleton deliberately survives page navigation;
/// callers must stop it explicitly when the test is complete.
class LocalTestServerService {
  LocalTestServerService._();

  static final LocalTestServerService instance = LocalTestServerService._();

  static const maxRequestBodyBytes = 1024 * 1024;
  static const maxEventCount = 300;

  final _changes = StreamController<LocalTestServerSnapshot>.broadcast(
    sync: true,
  );
  final _events = <LocalTestServerEvent>[];
  final _tcpClients = <Socket>{};
  final _tcpPeers = <Socket, String>{};

  HttpServer? _httpServer;
  ServerSocket? _tcpServer;
  StreamSubscription<HttpRequest>? _httpSubscription;
  StreamSubscription<Socket>? _tcpSubscription;
  Timer? _publishTimer;
  var _status = LocalTestServerStatus.stopped;
  var _mode = LocalTestServerMode.http;
  var _bindAddress = '0.0.0.0';
  var _port = 0;
  DateTime? _startedAt;
  var _requestCount = 0;
  var _connectionCount = 0;
  var _receivedBytes = 0;
  var _sentBytes = 0;
  String? _error;
  var _generation = 0;

  Stream<LocalTestServerSnapshot> get changes => _changes.stream;

  LocalTestServerSnapshot get snapshot => LocalTestServerSnapshot(
    status: _status,
    mode: _mode,
    bindAddress: _bindAddress,
    port: _port,
    startedAt: _startedAt,
    requestCount: _requestCount,
    connectionCount: _connectionCount,
    activeConnections: _tcpClients.length,
    receivedBytes: _receivedBytes,
    sentBytes: _sentBytes,
    events: List.unmodifiable(_events),
    error: _error,
  );

  Future<void> start({
    required LocalTestServerMode mode,
    required int port,
    String bindAddress = '0.0.0.0',
    String httpResponseBody = 'Hello from local test server',
    String httpContentType = 'text/plain; charset=utf-8',
  }) async {
    if (port < 0 || port > 65535) {
      throw const FormatException('端口必须为 0～65535');
    }
    final normalizedBind = bindAddress.trim();
    if (normalizedBind.isEmpty) {
      throw const FormatException('绑定地址不能为空');
    }
    ContentType? contentType;
    if (mode == LocalTestServerMode.http) {
      try {
        contentType = ContentType.parse(httpContentType);
      } on FormatException {
        throw const FormatException('HTTP Content-Type 格式无效');
      }
    }

    await _closeResources();
    _generation += 1;
    final generation = _generation;
    _mode = mode;
    _bindAddress = normalizedBind;
    _port = port;
    _startedAt = null;
    _requestCount = 0;
    _connectionCount = 0;
    _receivedBytes = 0;
    _sentBytes = 0;
    _error = null;
    _events.clear();
    _status = LocalTestServerStatus.starting;
    _publish(immediate: true);

    try {
      if (mode == LocalTestServerMode.http) {
        final server = await HttpServer.bind(
          normalizedBind,
          port,
          shared: false,
        );
        _httpServer = server;
        _port = server.port;
        _httpSubscription = server.listen(
          (request) => unawaited(
            _handleHttpRequest(
              request,
              generation,
              httpResponseBody,
              contentType!,
            ),
          ),
          onError: (Object error) => _recordRuntimeError(error, generation),
          cancelOnError: false,
        );
      } else {
        final server = await ServerSocket.bind(
          normalizedBind,
          port,
          shared: false,
        );
        _tcpServer = server;
        _port = server.port;
        _tcpSubscription = server.listen(
          (socket) => _acceptTcp(socket, generation),
          onError: (Object error) => _recordRuntimeError(error, generation),
          cancelOnError: false,
        );
      }
      if (generation != _generation) return;
      _startedAt = DateTime.now();
      _status = LocalTestServerStatus.listening;
      _addEvent(
        kind: 'SYS',
        peer: '$_bindAddress:$_port',
        summary: mode == LocalTestServerMode.http
            ? 'HTTP 服务已开始监听'
            : 'TCP Echo 服务已开始监听',
        immediate: true,
      );
    } on Object catch (error) {
      await _closeResources();
      if (generation == _generation) {
        _status = LocalTestServerStatus.failed;
        _error = _cleanError(error);
        _addEvent(
          kind: 'ERR',
          peer: '$normalizedBind:$port',
          summary: '监听启动失败',
          detail: _error,
          immediate: true,
        );
      }
      rethrow;
    }
  }

  Future<void> stop() async {
    if (_status == LocalTestServerStatus.stopped ||
        _status == LocalTestServerStatus.stopping) {
      return;
    }
    _status = LocalTestServerStatus.stopping;
    _publish(immediate: true);
    _generation += 1;
    await _closeResources();
    _startedAt = null;
    _status = LocalTestServerStatus.stopped;
    _error = null;
    _addEvent(
      kind: 'SYS',
      peer: '$_bindAddress:$_port',
      summary: '服务已停止',
      immediate: true,
    );
  }

  void clearEvents() {
    _events.clear();
    _publish(immediate: true);
  }

  Future<List<String>> discoverLocalIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final values = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final value = address.address;
        if (value != '0.0.0.0' && !value.startsWith('169.254.')) {
          values.add(value);
        }
      }
    }
    final result = values.toList();
    result.sort((left, right) {
      final leftPrivate = _isPrivateIpv4(left);
      final rightPrivate = _isPrivateIpv4(right);
      if (leftPrivate != rightPrivate) return leftPrivate ? -1 : 1;
      return left.compareTo(right);
    });
    return result;
  }

  Future<void> _handleHttpRequest(
    HttpRequest request,
    int generation,
    String responseBody,
    ContentType contentType,
  ) async {
    if (generation != _generation) {
      await request.response.close();
      return;
    }
    final peer = _httpPeer(request);
    _requestCount += 1;
    var bodyBytes = 0;
    var tooLarge = request.contentLength > maxRequestBodyBytes;
    try {
      await for (final chunk in request) {
        bodyBytes += chunk.length;
        _receivedBytes += chunk.length;
        if (bodyBytes > maxRequestBodyBytes) tooLarge = true;
      }

      final detail = _httpDetail(request, bodyBytes);
      if (tooLarge) {
        final payload = utf8.encode(
          jsonEncode({'ok': false, 'error': 'request body too large'}),
        );
        request.response.statusCode = HttpStatus.requestEntityTooLarge;
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('cache-control', 'no-store');
        request.response.add(payload);
        await request.response.close();
        _sentBytes += payload.length;
        _addEvent(
          kind: 'WARN',
          peer: peer,
          summary: '${request.method} ${_safeRequestTarget(request.uri)} · 413',
          detail: detail,
        );
        return;
      }

      final payload = utf8.encode(responseBody);
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = contentType;
      request.response.headers.set('cache-control', 'no-store');
      request.response.headers.set('access-control-allow-origin', '*');
      request.response.headers.set('x-local-test-server', 'active');
      if (request.method == 'OPTIONS') {
        request.response.headers.set(
          'access-control-allow-methods',
          'GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS',
        );
        request.response.headers.set(
          'access-control-allow-headers',
          request.headers.value('access-control-request-headers') ?? '*',
        );
      } else if (request.method != 'HEAD') {
        request.response.add(payload);
        _sentBytes += payload.length;
      }
      await request.response.close();
      _addEvent(
        kind: 'HTTP',
        peer: peer,
        summary: '${request.method} ${_safeRequestTarget(request.uri)} · 200',
        detail: detail,
      );
    } on Object catch (error) {
      _addEvent(
        kind: 'ERR',
        peer: peer,
        summary: '${request.method} ${_safeRequestTarget(request.uri)} 处理失败',
        detail: _cleanError(error),
      );
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } on Object {
        // The peer may have disconnected while the response was being written.
      }
    }
  }

  void _acceptTcp(Socket socket, int generation) {
    if (generation != _generation) {
      socket.destroy();
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final peer = '${socket.remoteAddress.address}:${socket.remotePort}';
    _tcpClients.add(socket);
    _tcpPeers[socket] = peer;
    _connectionCount += 1;
    _addEvent(kind: 'OPEN', peer: peer, summary: 'TCP 客户端已连接');
    socket.listen(
      (data) => unawaited(_echoTcp(socket, data, generation)),
      onError: (Object error) {
        _addEvent(
          kind: 'ERR',
          peer: peer,
          summary: 'TCP 连接错误',
          detail: _cleanError(error),
        );
        _removeTcpClient(socket, peer, generation);
      },
      onDone: () => _removeTcpClient(socket, peer, generation),
      cancelOnError: true,
    );
  }

  Future<void> _echoTcp(Socket socket, List<int> data, int generation) async {
    if (generation != _generation || !_tcpClients.contains(socket)) return;
    final peer = _tcpPeers[socket] ?? '未知客户端';
    final bytes = Uint8List.fromList(data);
    _receivedBytes += bytes.length;
    try {
      socket.add(bytes);
      await socket.flush();
      _sentBytes += bytes.length;
      _addEvent(
        kind: 'ECHO',
        peer: peer,
        summary: '收到并回显 ${bytes.length} B',
        detail: _payloadPreview(bytes),
      );
    } on Object catch (error) {
      _addEvent(
        kind: 'ERR',
        peer: peer,
        summary: 'TCP 回显失败',
        detail: _cleanError(error),
      );
      _removeTcpClient(socket, peer, generation);
    }
  }

  void _removeTcpClient(Socket socket, String peer, int generation) {
    if (!_tcpClients.remove(socket)) return;
    _tcpPeers.remove(socket);
    socket.destroy();
    if (generation == _generation) {
      _addEvent(kind: 'CLOSE', peer: peer, summary: 'TCP 客户端已断开');
    }
  }

  Future<void> _closeResources() async {
    _publishTimer?.cancel();
    _publishTimer = null;
    await _httpSubscription?.cancel();
    _httpSubscription = null;
    await _tcpSubscription?.cancel();
    _tcpSubscription = null;
    await _httpServer?.close(force: true);
    _httpServer = null;
    await _tcpServer?.close();
    _tcpServer = null;
    for (final socket in List<Socket>.from(_tcpClients)) {
      socket.destroy();
    }
    _tcpClients.clear();
    _tcpPeers.clear();
  }

  void _recordRuntimeError(Object error, int generation) {
    if (generation != _generation) return;
    _addEvent(
      kind: 'ERR',
      peer: '$_bindAddress:$_port',
      summary: '监听器错误',
      detail: _cleanError(error),
    );
  }

  void _addEvent({
    required String kind,
    required String peer,
    required String summary,
    String? detail,
    bool immediate = false,
  }) {
    _events.insert(
      0,
      LocalTestServerEvent(
        time: DateTime.now(),
        kind: kind,
        peer: peer,
        summary: summary,
        detail: detail,
      ),
    );
    if (_events.length > maxEventCount) {
      _events.removeRange(maxEventCount, _events.length);
    }
    _publish(immediate: immediate);
  }

  void _publish({bool immediate = false}) {
    if (immediate) {
      _publishTimer?.cancel();
      _publishTimer = null;
      if (!_changes.isClosed) _changes.add(snapshot);
      return;
    }
    _publishTimer ??= Timer(const Duration(milliseconds: 80), () {
      _publishTimer = null;
      if (!_changes.isClosed) _changes.add(snapshot);
    });
  }

  String _httpPeer(HttpRequest request) {
    final info = request.connectionInfo;
    return info == null
        ? '未知来源'
        : '${info.remoteAddress.address}:${info.remotePort}';
  }

  String _httpDetail(HttpRequest request, int bodyBytes) {
    const safeHeaders = [
      'host',
      'user-agent',
      'x-forwarded-for',
      'x-forwarded-host',
      'x-forwarded-proto',
      'content-type',
      'content-length',
    ];
    final lines = <String>[];
    for (final name in safeHeaders) {
      final value = request.headers.value(name);
      if (value != null && value.isNotEmpty) lines.add('$name: $value');
    }
    if (bodyBytes > 0) lines.add('body-size: $bodyBytes B');
    return lines.isEmpty ? '未携带可展示的请求头或正文' : lines.join('\n');
  }

  String _safeRequestTarget(Uri uri) {
    if (!uri.hasQuery) return uri.path.isEmpty ? '/' : uri.path;
    final safePairs = <String>[];
    for (final pair in uri.query.split('&')) {
      final separator = pair.indexOf('=');
      final encodedName = separator < 0 ? pair : pair.substring(0, separator);
      final name = Uri.decodeQueryComponent(encodedName);
      final sensitive = RegExp(
        r'(token|secret|password|passwd|authorization|api[_-]?key|signature)',
        caseSensitive: false,
      ).hasMatch(name);
      safePairs.add(sensitive ? '$encodedName=<redacted>' : pair);
    }
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '$path?${safePairs.join('&')}';
  }

  String _payloadPreview(Uint8List bytes) {
    final shown = bytes.length <= 256 ? bytes : bytes.sublist(0, 256);
    final text = utf8.decode(shown, allowMalformed: true);
    final printable = text.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'),
      '·',
    );
    return bytes.length > shown.length ? '$printable…' : printable;
  }

  String _cleanError(Object error) {
    final value = error.toString();
    return value.replaceFirst(RegExp(r'^(Exception|SocketException):\s*'), '');
  }

  bool _isPrivateIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }
}
