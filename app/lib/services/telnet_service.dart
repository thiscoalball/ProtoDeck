import 'dart:async';
import 'dart:convert';
import 'dart:io';

class TelnetConnection {
  TelnetConnection._(this._socket) {
    _output = _displayBytes.stream.transform(
      const Utf8Decoder(allowMalformed: true),
    );
    _socket.listen(
      _decode,
      onError: (Object error, StackTrace stackTrace) {
        if (!_displayBytes.isClosed) {
          _displayBytes.add(utf8.encode('\r\n[Connection error] $error\r\n'));
        }
      },
      onDone: () {
        if (!_displayBytes.isClosed) {
          _displayBytes.add(
            utf8.encode('\r\n[Remote closed the connection]\r\n'),
          );
          _displayBytes.close();
        }
      },
      cancelOnError: false,
    );
  }

  static const _iac = 255;
  static const _dont = 254;
  static const _do = 253;
  static const _wont = 252;
  static const _will = 251;
  static const _sb = 250;
  static const _se = 240;
  static const _echo = 1;
  static const _suppressGoAhead = 3;
  static const _terminalType = 24;
  static const _windowSize = 31;

  final Socket _socket;
  final StreamController<List<int>> _displayBytes =
      StreamController<List<int>>();
  final List<int> _pending = [];
  late final Stream<String> _output;
  bool _closed = false;
  int _width = 80;
  int _height = 24;

  Stream<String> get output => _output;

  static Future<TelnetConnection> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return TelnetConnection._(socket);
  }

  void sendText(String text) {
    if (_closed) return;
    final encoded = utf8.encode(text);
    final escaped = <int>[];
    for (final byte in encoded) {
      escaped.add(byte);
      if (byte == _iac) escaped.add(_iac);
    }
    _socket.add(escaped);
  }

  void resize(int width, int height) {
    _width = width.clamp(1, 65535);
    _height = height.clamp(1, 65535);
    _sendWindowSize();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _socket.close();
    if (!_displayBytes.isClosed) await _displayBytes.close();
  }

  void _decode(List<int> bytes) {
    _pending.addAll(bytes);
    final visible = <int>[];
    var cursor = 0;
    while (cursor < _pending.length) {
      if (_pending[cursor] != _iac) {
        visible.add(_pending[cursor++]);
        continue;
      }
      if (cursor + 1 >= _pending.length) break;
      final command = _pending[cursor + 1];
      if (command == _iac) {
        visible.add(_iac);
        cursor += 2;
        continue;
      }
      if (command == _do ||
          command == _dont ||
          command == _will ||
          command == _wont) {
        if (cursor + 2 >= _pending.length) break;
        _negotiate(command, _pending[cursor + 2]);
        cursor += 3;
        continue;
      }
      if (command == _sb) {
        final end = _subnegotiationEnd(cursor + 2);
        if (end == null) break;
        _handleSubnegotiation(_pending.sublist(cursor + 2, end));
        cursor = end + 2;
        continue;
      }
      cursor += 2;
    }
    if (cursor > 0) _pending.removeRange(0, cursor);
    if (visible.isNotEmpty && !_displayBytes.isClosed) {
      _displayBytes.add(visible);
    }
  }

  int? _subnegotiationEnd(int start) {
    for (var index = start; index + 1 < _pending.length; index++) {
      if (_pending[index] == _iac && _pending[index + 1] == _se) return index;
    }
    return null;
  }

  void _negotiate(int command, int option) {
    if (command == _do) {
      final supported =
          option == _suppressGoAhead ||
          option == _terminalType ||
          option == _windowSize;
      _sendCommand(supported ? _will : _wont, option);
      if (supported && option == _windowSize) _sendWindowSize();
    } else if (command == _will) {
      final supported = option == _echo || option == _suppressGoAhead;
      _sendCommand(supported ? _do : _dont, option);
    } else if (command == _dont) {
      _sendCommand(_wont, option);
    } else if (command == _wont) {
      _sendCommand(_dont, option);
    }
  }

  void _handleSubnegotiation(List<int> payload) {
    if (payload.length >= 2 &&
        payload.first == _terminalType &&
        payload[1] == 1) {
      _socket.add([
        _iac,
        _sb,
        _terminalType,
        0,
        ...ascii.encode('xterm-256color'),
        _iac,
        _se,
      ]);
    }
  }

  void _sendWindowSize() {
    if (_closed) return;
    _socket.add([
      _iac,
      _sb,
      _windowSize,
      (_width >> 8) & 0xff,
      _width & 0xff,
      (_height >> 8) & 0xff,
      _height & 0xff,
      _iac,
      _se,
    ]);
  }

  void _sendCommand(int command, int option) {
    if (!_closed) _socket.add([_iac, command, option]);
  }
}

/// Keeps one interactive Telnet connection alive while the application runs.
/// UI pages can detach and reattach without closing the socket.
class TelnetSessionRegistry {
  TelnetSessionRegistry._();

  static final TelnetSessionRegistry instance = TelnetSessionRegistry._();
  static const _maxTranscriptCharacters = 500000;

  final _output = StreamController<String>.broadcast(sync: true);
  TelnetConnection? _connection;
  StreamSubscription<String>? _subscription;
  String _transcript = '';
  String? _host;
  int? _port;
  bool _connected = false;

  Stream<String> get output => _output.stream;
  String get transcript => _transcript;
  String? get host => _host;
  int? get port => _port;
  bool get connected => _connected;

  Future<void> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await disconnect(clearTranscript: true);
    final connection = await TelnetConnection.connect(
      host,
      port,
      timeout: timeout,
    );
    _connection = connection;
    _host = host;
    _port = port;
    _connected = true;
    _append('[Connected $host:$port]\r\n');
    _subscription = connection.output.listen(
      _append,
      onError: (Object error) {
        _append('\r\n[Connection error] $error\r\n');
        _connected = false;
      },
      onDone: () {
        _connected = false;
        _append('\r\n[Session ended]\r\n');
      },
      cancelOnError: false,
    );
  }

  void sendText(String text) => _connection?.sendText(text);

  void resize(int width, int height) => _connection?.resize(width, height);

  Future<void> disconnect({bool clearTranscript = false}) async {
    await _subscription?.cancel();
    _subscription = null;
    await _connection?.close();
    _connection = null;
    _connected = false;
    if (clearTranscript) _transcript = '';
  }

  void clearTranscript() {
    _transcript = '';
    _output.add('\x1b[2J\x1b[H');
  }

  void _append(String value) {
    _transcript += value;
    if (_transcript.length > _maxTranscriptCharacters) {
      _transcript = _transcript.substring(
        _transcript.length - _maxTranscriptCharacters,
      );
    }
    if (!_output.isClosed) _output.add(value);
  }
}
