import 'dart:async';

import 'api_workbench_service.dart';

/// Keeps realtime API sessions alive while their editor pages are temporarily
/// removed from the navigation tree.
///
/// Message payloads only live in memory. They are deliberately not written to
/// the workspace store because realtime frames may contain credentials or
/// other sensitive data.
class ApiRealtimeSessionRegistry {
  ApiRealtimeSessionRegistry._() {
    _subscriptions.addAll([
      webSocket.messages.listen(_record),
      sse.messages.listen(_record),
      mqtt.messages.listen(_record),
    ]);
  }

  static final ApiRealtimeSessionRegistry instance =
      ApiRealtimeSessionRegistry._();

  final WebSocketDebugSession webSocket = WebSocketDebugSession();
  final SseDebugSession sse = SseDebugSession();
  final MqttDebugSession mqtt = MqttDebugSession();
  final _messages = StreamController<RealtimeMessage>.broadcast();
  final _connectionChanges = StreamController<int>.broadcast();
  final _history = <int, List<RealtimeMessage>>{1: [], 2: [], 3: []};
  final _connected = <int, bool>{1: false, 2: false, 3: false};
  final _subscriptions = <StreamSubscription<RealtimeMessage>>[];

  Stream<RealtimeMessage> get messages => _messages.stream;
  Stream<int> get connectionChanges => _connectionChanges.stream;

  bool isConnected(int protocol) => _connected[protocol] ?? false;

  List<RealtimeMessage> historyFor(int protocol) =>
      List.unmodifiable(_history[protocol] ?? const []);

  Future<void> connectWebSocket(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    await webSocket.connect(url, headers: headers);
    _setConnected(1, true);
  }

  Future<void> connectSse(
    String url, {
    Map<String, String> headers = const {},
    String method = 'GET',
    String body = '',
  }) async {
    await sse.connect(url, headers: headers, method: method, body: body);
    _setConnected(2, true);
  }

  Future<void> connectMqtt({
    required String host,
    required int port,
    required String clientId,
    String username = '',
    String password = '',
    bool tls = false,
    bool cleanSession = true,
  }) async {
    await mqtt.connect(
      host: host,
      port: port,
      clientId: clientId,
      username: username,
      password: password,
      tls: tls,
      cleanSession: cleanSession,
    );
    _setConnected(3, true);
  }

  Future<void> disconnect(int protocol) async {
    switch (protocol) {
      case 1:
        await webSocket.disconnect();
        break;
      case 2:
        await sse.disconnect();
        break;
      case 3:
        await mqtt.disconnect();
        break;
    }
    _setConnected(protocol, false);
  }

  void clearHistory(int protocol) => _history[protocol]?.clear();

  void _record(RealtimeMessage message) {
    final protocol = switch (message.protocol) {
      'WebSocket' => 1,
      'SSE' => 2,
      'MQTT' => 3,
      _ => 0,
    };
    if (protocol == 0) return;
    final history = _history[protocol]!;
    history.add(message);
    if (history.length > 2000) history.removeRange(0, history.length - 2000);
    if (message.direction == 'ERR' || _isClosedMessage(message)) {
      _setConnected(protocol, false);
    }
    if (!_messages.isClosed) _messages.add(message);
  }

  bool _isClosedMessage(RealtimeMessage message) {
    if (message.direction != 'SYS') return false;
    return message.data.contains('已关闭') ||
        message.data.contains('已结束') ||
        message.data.contains('closed');
  }

  void _setConnected(int protocol, bool value) {
    if (_connected[protocol] == value) return;
    _connected[protocol] = value;
    if (!_connectionChanges.isClosed) _connectionChanges.add(protocol);
  }
}
