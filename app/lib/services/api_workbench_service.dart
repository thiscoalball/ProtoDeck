import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ApiResponseData {
  const ApiResponseData({
    required this.statusCode,
    required this.reason,
    required this.headers,
    required this.body,
    required this.elapsed,
    required this.bytes,
    required this.finalUrl,
    required this.rawBytes,
    required this.cookies,
    required this.requestMethod,
    required this.requestHeaders,
    required this.requestBody,
  });

  final int statusCode;
  final String reason;
  final Map<String, List<String>> headers;
  final String body;
  final Duration elapsed;
  final int bytes;
  final Uri finalUrl;
  final Uint8List rawBytes;
  final List<Cookie> cookies;
  final String requestMethod;
  final Map<String, String> requestHeaders;
  final String requestBody;
}

class ApiWorkbenchService {
  HttpClient? _activeHttp;

  Future<ApiResponseData> request({
    required String method,
    required String url,
    Map<String, String> headers = const {},
    String body = '',
    Uint8List? bodyBytes,
    String? requestBodyPreview,
    Duration timeout = const Duration(seconds: 20),
    bool followRedirects = true,
    bool allowBadCertificates = false,
  }) async {
    final uri = Uri.parse(url.trim());
    if (!uri.hasScheme || !uri.hasAuthority) {
      throw const FormatException('URL 必须包含 http:// 或 https://');
    }
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = allowBadCertificates
          ? (_, _, _) => true
          : null;
    _activeHttp = client;
    final watch = Stopwatch()..start();
    try {
      final request = await client
          .openUrl(method.toUpperCase(), uri)
          .timeout(timeout);
      request.followRedirects = followRedirects;
      headers.forEach(request.headers.set);
      final outgoing = bodyBytes ?? Uint8List.fromList(utf8.encode(body));
      if (outgoing.isNotEmpty) request.add(outgoing);
      final response = await request.close().timeout(timeout);
      final bytes = await response.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (builder, chunk) => builder..add(chunk),
      );
      watch.stop();
      final data = bytes.takeBytes();
      final responseHeaders = <String, List<String>>{};
      response.headers.forEach(
        (name, values) => responseHeaders[name] = values,
      );
      return ApiResponseData(
        statusCode: response.statusCode,
        reason: response.reasonPhrase,
        headers: responseHeaders,
        body: _decodeBody(data, response.headers.contentType?.charset),
        elapsed: watch.elapsed,
        bytes: data.length,
        finalUrl: response.redirects.isEmpty
            ? uri
            : response.redirects.last.location,
        rawBytes: data,
        cookies: response.cookies,
        requestMethod: method.toUpperCase(),
        requestHeaders: Map.unmodifiable(headers),
        requestBody:
            requestBodyPreview ??
            (bodyBytes == null
                ? body
                : utf8.decode(bodyBytes, allowMalformed: true)),
      );
    } finally {
      client.close(force: false);
      if (identical(_activeHttp, client)) _activeHttp = null;
    }
  }

  void cancel() {
    _activeHttp?.close(force: true);
    _activeHttp = null;
  }

  String _decodeBody(Uint8List bytes, String? charset) {
    if (charset?.toLowerCase() == 'latin1' ||
        charset?.toLowerCase() == 'iso-8859-1') {
      return latin1.decode(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Map<String, String> parseHeaders(String input) {
    final result = <String, String>{};
    for (final line in const LineSplitter().convert(input)) {
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      final index = line.indexOf(':');
      if (index <= 0) throw FormatException('请求头格式错误：$line');
      result[line.substring(0, index).trim()] = line
          .substring(index + 1)
          .trim();
    }
    return result;
  }

  static String substitute(String input, Map<String, String> environment) {
    return input.replaceAllMapped(
      RegExp(r'\{\{([A-Za-z_][A-Za-z0-9_.-]*)\}\}'),
      (match) {
        return environment[match.group(1)] ?? match.group(0)!;
      },
    );
  }

  static String curl({
    required String method,
    required String url,
    required Map<String, String> headers,
    required String body,
  }) {
    String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
    final parts = <String>['curl', '-X', method.toUpperCase(), quote(url)];
    headers.forEach(
      (key, value) => parts.addAll(['-H', quote('$key: $value')]),
    );
    if (body.isNotEmpty) parts.addAll(['--data-raw', quote(body)]);
    return parts.join(' ');
  }
}

class RealtimeMessage {
  RealtimeMessage(
    this.direction,
    this.data, {
    DateTime? time,
    this.protocol = '',
    this.kind = 'text',
    this.channel,
    this.bytes,
    this.metadata = const {},
  }) : time = time ?? DateTime.now();
  final String direction;
  final String data;
  final DateTime time;
  final String protocol;
  final String kind;
  final String? channel;
  final Uint8List? bytes;
  final Map<String, Object?> metadata;

  int get size => bytes?.length ?? utf8.encode(data).length;

  String get prettyData {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(data));
    } on Object {
      return data;
    }
  }
}

class WebSocketDebugSession {
  final _messages = StreamController<RealtimeMessage>.broadcast();
  WebSocket? _socket;
  Stream<RealtimeMessage> get messages => _messages.stream;

  Future<void> connect(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    await disconnect();
    final socket = await WebSocket.connect(url, headers: headers);
    _socket = socket;
    _messages.add(
      RealtimeMessage(
        'SYS',
        'WebSocket 已连接 · ${socket.protocol ?? '无子协议'}',
        protocol: 'WebSocket',
        metadata: {'subprotocol': socket.protocol},
      ),
    );
    socket.listen(
      (data) {
        if (_messages.isClosed) return;
        if (data is List<int>) {
          final bytes = Uint8List.fromList(data);
          _messages.add(
            RealtimeMessage(
              'RX',
              utf8.decode(bytes, allowMalformed: true),
              protocol: 'WebSocket',
              kind: 'binary',
              bytes: bytes,
            ),
          );
        } else {
          final text = '$data';
          _messages.add(
            RealtimeMessage(
              'RX',
              text,
              protocol: 'WebSocket',
              kind: _looksLikeJson(text) ? 'json' : 'text',
            ),
          );
        }
      },
      onError: (Object error) {
        if (!_messages.isClosed) {
          _messages.add(
            RealtimeMessage('ERR', '$error', protocol: 'WebSocket'),
          );
        }
      },
      onDone: () {
        if (!_messages.isClosed) {
          _messages.add(
            RealtimeMessage(
              'SYS',
              '连接关闭 · code=${socket.closeCode} ${socket.closeReason ?? ''}',
              protocol: 'WebSocket',
              metadata: {
                'closeCode': socket.closeCode,
                'closeReason': socket.closeReason,
              },
            ),
          );
        }
      },
    );
  }

  void send(String data) {
    final socket = _socket ?? (throw StateError('WebSocket 尚未连接'));
    socket.add(data);
    _messages.add(
      RealtimeMessage(
        'TX',
        data,
        protocol: 'WebSocket',
        kind: _looksLikeJson(data) ? 'json' : 'text',
      ),
    );
  }

  void sendBinary(Uint8List data) {
    final socket = _socket ?? (throw StateError('WebSocket 尚未连接'));
    socket.add(data);
    _messages.add(
      RealtimeMessage(
        'TX',
        utf8.decode(data, allowMalformed: true),
        protocol: 'WebSocket',
        kind: 'binary',
        bytes: data,
      ),
    );
  }

  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
  }
}

bool _looksLikeJson(String value) {
  try {
    jsonDecode(value);
    return true;
  } on Object {
    return false;
  }
}

class SseDebugSession {
  final _messages = StreamController<RealtimeMessage>.broadcast();
  HttpClient? _client;
  StreamSubscription<String>? _subscription;
  final _eventData = <String>[];
  String? _eventName;
  String? _eventId;
  int? _retry;
  Stream<RealtimeMessage> get messages => _messages.stream;

  Future<void> connect(
    String url, {
    Map<String, String> headers = const {},
    String method = 'GET',
    String body = '',
  }) async {
    await disconnect();
    final client = HttpClient();
    _client = client;
    final request = await client.openUrl(method.toUpperCase(), Uri.parse(url));
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    headers.forEach(request.headers.set);
    if (body.isNotEmpty) request.add(utf8.encode(body));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('SSE HTTP ${response.statusCode}');
    }
    _messages.add(
      RealtimeMessage(
        'SYS',
        'SSE 已连接 · HTTP ${response.statusCode}',
        protocol: 'SSE',
        metadata: {
          'statusCode': response.statusCode,
          'contentType': response.headers.contentType?.toString(),
        },
      ),
    );
    _subscription = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _consumeLine,
          onError: (Object error) {
            if (!_messages.isClosed) {
              _messages.add(RealtimeMessage('ERR', '$error', protocol: 'SSE'));
            }
          },
          onDone: () {
            _flushEvent();
            if (!_messages.isClosed) {
              _messages.add(
                RealtimeMessage('SYS', 'SSE 流已结束', protocol: 'SSE'),
              );
            }
          },
        );
  }

  void _consumeLine(String line) {
    if (line.isEmpty) {
      _flushEvent();
      return;
    }
    if (line.startsWith(':')) return;
    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        _eventData.add(value);
        break;
      case 'event':
        _eventName = value;
        break;
      case 'id':
        _eventId = value;
        break;
      case 'retry':
        _retry = int.tryParse(value);
        break;
    }
  }

  void _flushEvent() {
    if (_eventData.isEmpty && _eventName == null && _eventId == null) return;
    final data = _eventData.join('\n');
    if (!_messages.isClosed) {
      _messages.add(
        RealtimeMessage(
          'RX',
          data,
          protocol: 'SSE',
          kind: _looksLikeJson(data) ? 'json' : 'text',
          channel: _eventName ?? 'message',
          metadata: {
            'event': _eventName ?? 'message',
            if (_eventId != null) 'id': _eventId,
            if (_retry != null) 'retry': _retry,
          },
        ),
      );
    }
    _eventData.clear();
    _eventName = null;
    _eventId = null;
    _retry = null;
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    _client?.close(force: true);
    _client = null;
    _eventData.clear();
    _eventName = null;
    _eventId = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
  }
}

class MqttDebugSession {
  final _messages = StreamController<RealtimeMessage>.broadcast();
  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  final _buffer = BytesBuilder(copy: false);
  int _packetId = 1;
  Timer? _keepAliveTimer;
  Stream<RealtimeMessage> get messages => _messages.stream;

  Future<void> connect({
    required String host,
    required int port,
    required String clientId,
    String username = '',
    String password = '',
    bool tls = false,
    int keepAliveSeconds = 60,
    bool cleanSession = true,
  }) async {
    await disconnect();
    final socket = tls
        ? await SecureSocket.connect(
            host,
            port,
            timeout: const Duration(seconds: 10),
          )
        : await Socket.connect(
            host,
            port,
            timeout: const Duration(seconds: 10),
          );
    _socket = socket;
    _subscription = socket.listen(_onData, onError: _onError, onDone: _onDone);
    var flags = cleanSession ? 0x02 : 0x00;
    if (username.isNotEmpty) flags |= 0x80;
    if (password.isNotEmpty) flags |= 0x40;
    final payload = BytesBuilder()
      ..add(_utf('MQTT'))
      ..add([4, flags, (keepAliveSeconds >> 8) & 0xff, keepAliveSeconds & 0xff])
      ..add(_utf(clientId));
    if (username.isNotEmpty) payload.add(_utf(username));
    if (password.isNotEmpty) payload.add(_utf(password));
    _writePacket(0x10, payload.takeBytes());
    _messages.add(
      RealtimeMessage('SYS', '正在连接 MQTT $host:$port', protocol: 'MQTT'),
    );
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      Duration(seconds: (keepAliveSeconds / 2).clamp(10, 60).round()),
      (_) {
        if (_socket != null) _socket!.add([0xC0, 0]);
      },
    );
  }

  void publish(
    String topic,
    Uint8List payload, {
    bool retain = false,
    int qos = 0,
  }) {
    if (qos < 0 || qos > 1) throw const FormatException('当前支持 QoS 0/1');
    final body = BytesBuilder()..add(_utf(topic));
    if (qos > 0) {
      final id = _nextPacketId();
      body.add([(id >> 8) & 0xff, id & 0xff]);
    }
    body.add(payload);
    final header = 0x30 | (qos << 1) | (retain ? 1 : 0);
    _writePacket(header, body.takeBytes());
    _messages.add(
      RealtimeMessage(
        'TX',
        utf8.decode(payload, allowMalformed: true),
        protocol: 'MQTT',
        kind: _looksLikeJson(utf8.decode(payload, allowMalformed: true))
            ? 'json'
            : 'text',
        channel: topic,
        bytes: payload,
        metadata: {'topic': topic, 'qos': qos, 'retain': retain},
      ),
    );
  }

  void subscribe(String topic, {int qos = 0}) {
    if (qos < 0 || qos > 1) throw const FormatException('当前支持 QoS 0/1');
    final id = _nextPacketId();
    final body = BytesBuilder()
      ..add([(id >> 8) & 0xff, id & 0xff])
      ..add(_utf(topic))
      ..add([qos]);
    _writePacket(0x82, body.takeBytes());
    _messages.add(
      RealtimeMessage(
        'SYS',
        '订阅 $topic · QoS $qos',
        protocol: 'MQTT',
        channel: topic,
        metadata: {'topic': topic, 'qos': qos, 'packetId': id},
      ),
    );
  }

  void unsubscribe(String topic) {
    final id = _nextPacketId();
    final body = BytesBuilder()
      ..add([(id >> 8) & 0xff, id & 0xff])
      ..add(_utf(topic));
    _writePacket(0xA2, body.takeBytes());
    _messages.add(
      RealtimeMessage(
        'SYS',
        '取消订阅 $topic',
        protocol: 'MQTT',
        channel: topic,
        metadata: {'topic': topic, 'packetId': id},
      ),
    );
  }

  void _onData(Uint8List data) {
    if (_messages.isClosed) return;
    _buffer.add(data);
    final all = _buffer.takeBytes();
    var offset = 0;
    while (offset + 2 <= all.length) {
      var multiplier = 1;
      var remaining = 0;
      var cursor = offset + 1;
      int encoded;
      do {
        if (cursor >= all.length) {
          _buffer.add(all.sublist(offset));
          return;
        }
        encoded = all[cursor++];
        remaining += (encoded & 127) * multiplier;
        multiplier *= 128;
      } while (encoded & 128 != 0);
      if (cursor + remaining > all.length) {
        _buffer.add(all.sublist(offset));
        return;
      }
      final header = all[offset];
      final payload = all.sublist(cursor, cursor + remaining);
      _handlePacket(header, payload);
      offset = cursor + remaining;
    }
    if (offset < all.length) _buffer.add(all.sublist(offset));
  }

  void _handlePacket(int header, Uint8List payload) {
    switch (header >> 4) {
      case 2:
        final ok = payload.length >= 2 && payload[1] == 0;
        _messages.add(
          RealtimeMessage(
            ok ? 'SYS' : 'ERR',
            ok
                ? 'MQTT 已连接'
                : 'CONNACK 拒绝：${payload.length > 1 ? payload[1] : -1}',
            protocol: 'MQTT',
            metadata: {
              'sessionPresent': payload.isNotEmpty && payload[0] & 1 != 0,
              'returnCode': payload.length > 1 ? payload[1] : -1,
            },
          ),
        );
        break;
      case 3:
        if (payload.length < 2) return;
        final length = payload[0] * 256 + payload[1];
        if (payload.length < 2 + length) return;
        final topic = utf8.decode(
          payload.sublist(2, 2 + length),
          allowMalformed: true,
        );
        final qos = (header >> 1) & 0x03;
        var cursor = 2 + length;
        int? packetId;
        if (qos > 0) {
          if (payload.length < cursor + 2) return;
          packetId = payload[cursor] * 256 + payload[cursor + 1];
          cursor += 2;
        }
        final body = payload.sublist(cursor);
        final text = utf8.decode(body, allowMalformed: true);
        _messages.add(
          RealtimeMessage(
            'RX',
            text,
            protocol: 'MQTT',
            kind: _looksLikeJson(text) ? 'json' : 'text',
            channel: topic,
            bytes: body,
            metadata: {
              'topic': topic,
              'qos': qos,
              'retain': header & 1 != 0,
              'duplicate': header & 8 != 0,
              'packetId': packetId,
            },
          ),
        );
        if (qos == 1 && packetId != null) {
          _socket?.add([0x40, 0x02, (packetId >> 8) & 0xff, packetId & 0xff]);
        }
        break;
      case 9:
        _messages.add(RealtimeMessage('SYS', '订阅已确认', protocol: 'MQTT'));
        break;
      case 11:
        _messages.add(RealtimeMessage('SYS', '取消订阅已确认', protocol: 'MQTT'));
        break;
      case 13:
        _messages.add(RealtimeMessage('SYS', 'PINGRESP', protocol: 'MQTT'));
        break;
      default:
        _messages.add(
          RealtimeMessage(
            'SYS',
            'MQTT packet type ${header >> 4} · ${payload.length} B',
            protocol: 'MQTT',
          ),
        );
    }
  }

  void _writePacket(int header, Uint8List payload) {
    final socket = _socket ?? (throw StateError('MQTT 尚未连接'));
    socket.add([header, ..._remainingLength(payload.length), ...payload]);
  }

  List<int> _utf(String value) {
    final bytes = utf8.encode(value);
    return [(bytes.length >> 8) & 0xff, bytes.length & 0xff, ...bytes];
  }

  List<int> _remainingLength(int value) {
    final result = <int>[];
    do {
      var digit = value % 128;
      value ~/= 128;
      if (value > 0) digit |= 128;
      result.add(digit);
    } while (value > 0);
    return result;
  }

  int _nextPacketId() {
    final value = _packetId++;
    if (_packetId > 65535) _packetId = 1;
    return value;
  }

  void _onError(Object error) {
    if (!_messages.isClosed) {
      _messages.add(RealtimeMessage('ERR', '$error', protocol: 'MQTT'));
    }
  }

  void _onDone() {
    if (!_messages.isClosed) {
      _messages.add(RealtimeMessage('SYS', 'MQTT 连接已关闭', protocol: 'MQTT'));
    }
  }

  Future<void> disconnect() async {
    if (_socket != null) runCatchingWriteDisconnect();
    await _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _buffer.clear();
  }

  void runCatchingWriteDisconnect() {
    try {
      _socket?.add([0xE0, 0]);
    } on Object {
      /* connection already gone */
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
  }
}
