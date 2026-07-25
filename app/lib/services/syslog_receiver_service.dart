import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum SyslogTransport { udp, tcp, both }

class SyslogMessage {
  const SyslogMessage({
    required this.receivedAt,
    required this.transport,
    required this.remoteAddress,
    required this.remotePort,
    required this.facility,
    required this.severity,
    required this.hostname,
    required this.appName,
    required this.processId,
    required this.messageId,
    required this.structuredData,
    required this.message,
    required this.raw,
    required this.standard,
  });

  final DateTime receivedAt;
  final String transport;
  final String remoteAddress;
  final int remotePort;
  final int facility;
  final int severity;
  final String hostname;
  final String appName;
  final String processId;
  final String messageId;
  final String structuredData;
  final String message;
  final String raw;
  final String standard;

  String get severityName => const [
    'Emergency',
    'Alert',
    'Critical',
    'Error',
    'Warning',
    'Notice',
    'Info',
    'Debug',
  ][severity.clamp(0, 7)];

  String get facilityName => const [
    'kernel',
    'user',
    'mail',
    'daemon',
    'auth',
    'syslog',
    'lpr',
    'news',
    'uucp',
    'clock',
    'authpriv',
    'ftp',
    'ntp',
    'audit',
    'alert',
    'clock2',
    'local0',
    'local1',
    'local2',
    'local3',
    'local4',
    'local5',
    'local6',
    'local7',
  ][facility.clamp(0, 23)];
}

class SyslogReceiverService {
  SyslogReceiverService._();

  static final SyslogReceiverService instance = SyslogReceiverService._();

  factory SyslogReceiverService() => instance;

  final _messages = StreamController<SyslogMessage>.broadcast();
  final _clients = <Socket>{};
  final _history = <SyslogMessage>[];
  RawDatagramSocket? _udp;
  ServerSocket? _tcp;
  bool _running = false;
  SyslogTransport _transport = SyslogTransport.both;
  int _port = 5514;
  int _receivedCount = 0;
  int _droppedCount = 0;

  Stream<SyslogMessage> get messages => _messages.stream;
  bool get running => _running;
  int get clientCount => _clients.length;
  SyslogTransport get transport => _transport;
  int get port => _port;
  int get receivedCount => _receivedCount;
  int get droppedCount => _droppedCount;
  List<SyslogMessage> get history => List.unmodifiable(_history);

  Future<void> start({
    required SyslogTransport transport,
    required int port,
    InternetAddress? bindAddress,
  }) async {
    if (_running) throw StateError('Syslog 接收器已经运行');
    if (port < 1 || port > 65535) throw const FormatException('端口必须是 1～65535');
    final address = bindAddress ?? InternetAddress.anyIPv4;
    _transport = transport;
    _port = port;
    _running = true;
    try {
      if (transport == SyslogTransport.udp ||
          transport == SyslogTransport.both) {
        _udp = await RawDatagramSocket.bind(address, port, reuseAddress: true);
        _udp!.listen((event) {
          if (event != RawSocketEvent.read) return;
          Datagram? datagram;
          while ((datagram = _udp?.receive()) != null) {
            final item = datagram!;
            _emit(item.data, 'UDP', item.address.address, item.port);
          }
        });
      }
      if (transport == SyslogTransport.tcp ||
          transport == SyslogTransport.both) {
        _tcp = await ServerSocket.bind(address, port, shared: true);
        _tcp!.listen(_acceptClient);
      }
    } on Object {
      await stop();
      rethrow;
    }
  }

  void _acceptClient(Socket socket) {
    _clients.add(socket);
    var buffer = Uint8List(0);
    socket.listen(
      (bytes) {
        final next = Uint8List(buffer.length + bytes.length)
          ..setRange(0, buffer.length, buffer)
          ..setRange(buffer.length, buffer.length + bytes.length, bytes);
        buffer = next;
        while (buffer.isNotEmpty) {
          final frame = _extractTcpFrame(buffer);
          if (frame == null) break;
          buffer = frame.$2;
          _emit(
            frame.$1,
            'TCP',
            socket.remoteAddress.address,
            socket.remotePort,
          );
        }
        if (buffer.length > 1024 * 1024) {
          _emit(
            buffer.sublist(0, 1024 * 1024),
            'TCP',
            socket.remoteAddress.address,
            socket.remotePort,
          );
          buffer = Uint8List(0);
        }
      },
      onDone: () {
        if (buffer.isNotEmpty)
          _emit(buffer, 'TCP', socket.remoteAddress.address, socket.remotePort);
        _clients.remove(socket);
      },
      onError: (_) => _clients.remove(socket),
      cancelOnError: true,
    );
  }

  (Uint8List, Uint8List)? _extractTcpFrame(Uint8List bytes) {
    var index = 0;
    while (index < bytes.length && bytes[index] >= 48 && bytes[index] <= 57)
      index++;
    if (index > 0 && index < bytes.length && bytes[index] == 32) {
      final length = int.tryParse(ascii.decode(bytes.sublist(0, index)));
      if (length != null && length >= 0 && length <= 1024 * 1024) {
        final start = index + 1;
        if (bytes.length < start + length) return null;
        return (
          Uint8List.fromList(bytes.sublist(start, start + length)),
          Uint8List.fromList(bytes.sublist(start + length)),
        );
      }
    }
    final newline = bytes.indexOf(10);
    if (newline < 0) return null;
    var end = newline;
    if (end > 0 && bytes[end - 1] == 13) end--;
    return (
      Uint8List.fromList(bytes.sublist(0, end)),
      Uint8List.fromList(bytes.sublist(newline + 1)),
    );
  }

  void _emit(Uint8List bytes, String transport, String address, int port) {
    if (!_running || bytes.isEmpty) return;
    final raw = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll(RegExp(r'[\r\n]+$'), '');
    final message = parseSyslog(
      raw,
      transport: transport,
      address: address,
      port: port,
    );
    _receivedCount++;
    if (_history.length >= 5000) {
      _history.removeAt(0);
      _droppedCount++;
    }
    _history.add(message);
    _messages.add(message);
  }

  void clearHistory() {
    _history.clear();
    _receivedCount = 0;
    _droppedCount = 0;
  }

  Future<void> stop() async {
    _running = false;
    _udp?.close();
    _udp = null;
    await _tcp?.close();
    _tcp = null;
    for (final client in _clients.toList()) {
      client.destroy();
    }
    _clients.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _messages.close();
  }
}

SyslogMessage parseSyslog(
  String raw, {
  String transport = 'UDP',
  String address = '',
  int port = 0,
  DateTime? receivedAt,
}) {
  var remainder = raw;
  var priority = 13;
  final priorityMatch = RegExp(r'^<(\d{1,3})>').firstMatch(remainder);
  if (priorityMatch != null) {
    final parsed = int.parse(priorityMatch.group(1)!);
    if (parsed <= 191) priority = parsed;
    remainder = remainder.substring(priorityMatch.end);
  }
  var hostname = '';
  var appName = '';
  var processId = '';
  var messageId = '';
  var structuredData = '';
  var message = remainder;
  var standard = 'Raw';

  final rfc5424 = RegExp(
    r'^(\d{1,3})\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.+)$',
    dotAll: true,
  ).firstMatch(remainder);
  if (rfc5424 != null) {
    standard = 'RFC 5424';
    hostname = _nil(rfc5424.group(3));
    appName = _nil(rfc5424.group(4));
    processId = _nil(rfc5424.group(5));
    messageId = _nil(rfc5424.group(6));
    var tail = rfc5424.group(7)!;
    if (tail.startsWith('-')) {
      tail = tail.substring(1).trimLeft();
    } else if (tail.startsWith('[')) {
      final end = _structuredDataEnd(tail);
      if (end >= 0) {
        structuredData = tail.substring(0, end + 1);
        tail = tail.substring(end + 1).trimLeft();
      }
    }
    if (tail.startsWith('\uFEFF')) tail = tail.substring(1);
    message = tail;
  } else {
    final rfc3164 = RegExp(
      r'^[A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+(\S+)\s+(.+)$',
      dotAll: true,
    ).firstMatch(remainder);
    if (rfc3164 != null) {
      standard = 'RFC 3164';
      hostname = rfc3164.group(1)!;
      final body = rfc3164.group(2)!;
      final tag = RegExp(
        r'^([^:\s\[]+)(?:\[(\d+)\])?:\s?(.*)$',
        dotAll: true,
      ).firstMatch(body);
      if (tag != null) {
        appName = tag.group(1)!;
        processId = tag.group(2) ?? '';
        message = tag.group(3) ?? '';
      } else {
        message = body;
      }
    }
  }
  return SyslogMessage(
    receivedAt: receivedAt ?? DateTime.now(),
    transport: transport,
    remoteAddress: address,
    remotePort: port,
    facility: priority ~/ 8,
    severity: priority % 8,
    hostname: hostname,
    appName: appName,
    processId: processId,
    messageId: messageId,
    structuredData: structuredData,
    message: message,
    raw: raw,
    standard: standard,
  );
}

String _nil(String? value) => value == '-' ? '' : value ?? '';

int _structuredDataEnd(String value) {
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == '\\' && quoted) {
      escaped = true;
      continue;
    }
    if (char == '"') {
      quoted = !quoted;
      continue;
    }
    if (quoted) continue;
    if (char == '[') depth++;
    if (char == ']') {
      depth--;
      if (depth == 0 && (i + 1 == value.length || value[i + 1] != '['))
        return i;
    }
  }
  return -1;
}
