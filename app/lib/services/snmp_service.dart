import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' show AESEngine, KeyParameter;

enum SnmpOperation { get, getNext, getBulk }

enum SnmpV3SecurityLevel { noAuthNoPriv, authNoPriv, authPriv }

enum SnmpV3AuthProtocol { md5, sha1, sha256 }

class SnmpV3Credentials {
  const SnmpV3Credentials({
    required this.username,
    required this.securityLevel,
    this.authProtocol = SnmpV3AuthProtocol.sha1,
    this.authPassword = '',
    this.privacyPassword = '',
  });
  final String username;
  final SnmpV3SecurityLevel securityLevel;
  final SnmpV3AuthProtocol authProtocol;
  final String authPassword;
  final String privacyPassword;
}

class SnmpVariable {
  const SnmpVariable({
    required this.oid,
    required this.type,
    required this.value,
  });
  final String oid;
  final String type;
  final String value;
}

class SnmpResponse {
  const SnmpResponse({
    required this.requestId,
    required this.variables,
    required this.elapsed,
    required this.address,
  });
  final int requestId;
  final List<SnmpVariable> variables;
  final Duration elapsed;
  final String address;
}

class SnmpService {
  RawDatagramSocket? _socket;
  bool _cancelled = false;
  final _random = Random.secure();

  void cancel() {
    _cancelled = true;
    _socket?.close();
    _socket = null;
  }

  Future<SnmpResponse> request({
    required String host,
    required String community,
    required List<String> oids,
    int port = 161,
    SnmpOperation operation = SnmpOperation.get,
    int maxRepetitions = 20,
    Duration timeout = const Duration(seconds: 3),
    int retries = 1,
  }) async {
    if (host.trim().isEmpty) throw const FormatException('SNMP 主机不能为空');
    if (community.isEmpty) throw const FormatException('Community 不能为空');
    if (oids.isEmpty) throw const FormatException('至少输入一个 OID');
    for (final oid in oids) {
      _encodeOid(oid);
    }
    _cancelled = false;
    final addresses = await InternetAddress.lookup(
      host.trim(),
    ).timeout(timeout);
    if (addresses.isEmpty) throw SocketException('无法解析 $host');
    final address = addresses.first;
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      if (_cancelled) throw const SnmpCancelled();
      final requestId = _random.nextInt(0x3FFFFFFF) + 1;
      final packet = _buildV2cRequest(
        community,
        requestId,
        oids,
        operation,
        maxRepetitions,
      );
      final socket = await RawDatagramSocket.bind(
        address.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0,
      );
      _socket = socket;
      final watch = Stopwatch()..start();
      try {
        socket.send(packet, address, port);
        final datagram = await _receive(socket, timeout);
        watch.stop();
        if (datagram.address.address != address.address) continue;
        final decoded = _decodeV2cResponse(datagram.data);
        if (decoded.$1 != requestId) continue;
        return SnmpResponse(
          requestId: requestId,
          variables: decoded.$2,
          elapsed: watch.elapsed,
          address: datagram.address.address,
        );
      } on Object catch (error) {
        lastError = error;
      } finally {
        socket.close();
        if (identical(_socket, socket)) _socket = null;
      }
    }
    if (_cancelled) throw const SnmpCancelled();
    throw lastError ?? TimeoutException('SNMP 查询超时', timeout);
  }

  Future<SnmpResponse> requestV3({
    required String host,
    required SnmpV3Credentials credentials,
    required List<String> oids,
    int port = 161,
    SnmpOperation operation = SnmpOperation.get,
    int maxRepetitions = 20,
    Duration timeout = const Duration(seconds: 4),
    int retries = 1,
  }) async {
    if (host.trim().isEmpty) throw const FormatException('SNMP 主机不能为空');
    _validateV3Credentials(credentials);
    for (final oid in oids) _encodeOid(oid);
    _cancelled = false;
    final addresses = await InternetAddress.lookup(
      host.trim(),
    ).timeout(timeout);
    if (addresses.isEmpty) throw SocketException('无法解析 $host');
    final address = addresses.first;
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      if (_cancelled) throw const SnmpCancelled();
      try {
        final engine = await _discoverV3(address, port, timeout);
        return await _requestV3WithEngine(
          address: address,
          port: port,
          credentials: credentials,
          engine: engine,
          oids: oids,
          operation: operation,
          maxRepetitions: maxRepetitions,
          timeout: timeout,
        );
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (_cancelled) throw const SnmpCancelled();
    throw lastError ?? TimeoutException('SNMPv3 查询超时', timeout);
  }

  Future<SnmpResponse> _requestV3WithEngine({
    required InternetAddress address,
    required int port,
    required SnmpV3Credentials credentials,
    required _V3Engine engine,
    required List<String> oids,
    required SnmpOperation operation,
    required int maxRepetitions,
    required Duration timeout,
  }) async {
    final requestId = _random.nextInt(0x3FFFFFFF) + 1;
    final packet = _buildV3Request(
      engine,
      credentials,
      requestId,
      oids,
      operation,
      maxRepetitions,
      _random,
    );
    final watch = Stopwatch()..start();
    final datagram = await _exchange(address, port, packet, timeout);
    watch.stop();
    final decoded = _decodeV3Response(datagram.data, credentials, engine);
    if (decoded.$1 != requestId)
      throw const FormatException('SNMPv3 Request ID 不匹配');
    return SnmpResponse(
      requestId: requestId,
      variables: decoded.$2,
      elapsed: watch.elapsed,
      address: datagram.address.address,
    );
  }

  Stream<List<SnmpVariable>> walkV3({
    required String host,
    required SnmpV3Credentials credentials,
    required String rootOid,
    int port = 161,
    int maxRows = 10000,
    int maxRepetitions = 20,
    Duration timeout = const Duration(seconds: 4),
  }) async* {
    _cancelled = false;
    if (host.trim().isEmpty) throw const FormatException('SNMP 主机不能为空');
    _validateV3Credentials(credentials);
    final addresses = await InternetAddress.lookup(
      host.trim(),
    ).timeout(timeout);
    if (addresses.isEmpty) throw SocketException('无法解析 $host');
    final address = addresses.first;
    final engine = await _discoverV3(address, port, timeout);
    var current = _normalizeOid(rootOid);
    final root = '$current.';
    final rows = <SnmpVariable>[];
    while (!_cancelled && rows.length < maxRows) {
      final response = await _requestV3WithEngine(
        address: address,
        port: port,
        credentials: credentials,
        engine: engine,
        oids: [current],
        operation: SnmpOperation.getBulk,
        maxRepetitions: maxRepetitions,
        timeout: timeout,
      );
      if (response.variables.isEmpty) break;
      var advanced = false;
      for (final next in response.variables) {
        final normalized = _normalizeOid(next.oid);
        if (!(normalized == _normalizeOid(rootOid) ||
            normalized.startsWith(root))) {
          break;
        }
        if (_compareOid(normalized, current) <= 0) continue;
        rows.add(next);
        current = normalized;
        advanced = true;
        if (rows.length >= maxRows) break;
      }
      if (!advanced) break;
      yield List.unmodifiable(rows);
    }
    if (_cancelled) throw const SnmpCancelled();
  }

  Future<_V3Engine> _discoverV3(
    InternetAddress address,
    int port,
    Duration timeout,
  ) async {
    final requestId = _random.nextInt(0x3FFFFFFF) + 1;
    final packet = _buildV3Discovery(requestId);
    final response = await _exchange(address, port, packet, timeout);
    final envelope = _decodeV3Envelope(response.data);
    if (envelope.engineId.isEmpty)
      throw const FormatException('SNMPv3 Engine Discovery 未返回 Engine ID');
    return _V3Engine(
      envelope.engineId,
      envelope.engineBoots,
      envelope.engineTime,
    );
  }

  Future<Datagram> _exchange(
    InternetAddress address,
    int port,
    Uint8List packet,
    Duration timeout,
  ) async {
    if (_cancelled) throw const SnmpCancelled();
    final socket = await RawDatagramSocket.bind(
      address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    _socket = socket;
    try {
      socket.send(packet, address, port);
      return await _receive(socket, timeout);
    } finally {
      socket.close();
      if (identical(_socket, socket)) _socket = null;
    }
  }

  Stream<List<SnmpVariable>> walk({
    required String host,
    required String community,
    required String rootOid,
    int port = 161,
    int maxRows = 10000,
    int maxRepetitions = 20,
    Duration timeout = const Duration(seconds: 3),
  }) async* {
    _cancelled = false;
    var current = _normalizeOid(rootOid);
    final root = current == '.' ? '.' : '$current.';
    final rows = <SnmpVariable>[];
    while (!_cancelled && rows.length < maxRows) {
      final response = await request(
        host: host,
        community: community,
        oids: [current],
        port: port,
        operation: SnmpOperation.getBulk,
        maxRepetitions: maxRepetitions,
        timeout: timeout,
        retries: 1,
      );
      if (response.variables.isEmpty) break;
      var advanced = false;
      for (final next in response.variables) {
        final normalized = _normalizeOid(next.oid);
        if (!(normalized == _normalizeOid(rootOid) ||
            normalized.startsWith(root))) {
          break;
        }
        if (_compareOid(normalized, current) <= 0) continue;
        rows.add(next);
        current = normalized;
        advanced = true;
        if (rows.length >= maxRows) break;
      }
      if (!advanced) break;
      yield List.unmodifiable(rows);
    }
    if (_cancelled) throw const SnmpCancelled();
  }

  Future<Datagram> _receive(RawDatagramSocket socket, Duration timeout) {
    final completer = Completer<Datagram>();
    late StreamSubscription<RawSocketEvent> subscription;
    subscription = socket.listen(
      (event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final value = socket.receive();
        if (value != null) completer.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    return completer.future
        .timeout(
          timeout,
          onTimeout: () => throw TimeoutException('SNMP 查询超时', timeout),
        )
        .whenComplete(subscription.cancel);
  }
}

void _validateV3Credentials(SnmpV3Credentials credentials) {
  if (credentials.username.trim().isEmpty) {
    throw const FormatException('SNMPv3 用户名不能为空');
  }
  if (credentials.securityLevel != SnmpV3SecurityLevel.noAuthNoPriv &&
      credentials.authPassword.length < 8) {
    throw const FormatException('SNMPv3 认证密码至少需要 8 个字符');
  }
  if (credentials.securityLevel == SnmpV3SecurityLevel.authPriv &&
      credentials.privacyPassword.length < 8) {
    throw const FormatException('SNMPv3 隐私密码至少需要 8 个字符');
  }
}

class SnmpCancelled implements Exception {
  const SnmpCancelled();
  @override
  String toString() => 'SNMP 任务已停止';
}

Uint8List _buildV2cRequest(
  String community,
  int requestId,
  List<String> oids,
  SnmpOperation operation,
  int maxRepetitions,
) {
  final variables = _sequence([
    for (final oid in oids)
      _sequence([_tlv(0x06, _encodeOid(oid)), _tlv(0x05, Uint8List(0))]),
  ]);
  final pduBody = <Uint8List>[
    _integer(requestId),
    _integer(0),
    _integer(
      operation == SnmpOperation.getBulk ? maxRepetitions.clamp(1, 100) : 0,
    ),
    variables,
  ];
  final pduTag = switch (operation) {
    SnmpOperation.get => 0xA0,
    SnmpOperation.getNext => 0xA1,
    SnmpOperation.getBulk => 0xA5,
  };
  return _sequence([
    _integer(1),
    _tlv(0x04, Uint8List.fromList(utf8.encode(community))),
    _tlv(pduTag, _concat(pduBody)),
  ]);
}

(int, List<SnmpVariable>) _decodeV2cResponse(Uint8List bytes) {
  final top = _BerReader(bytes).read();
  if (top.tag != 0x30) throw const FormatException('SNMP 响应不是 BER Sequence');
  final message = _BerReader(top.value);
  final version = _decodeInteger(message.read());
  if (version != 1) throw FormatException('SNMP 响应版本不匹配：$version');
  message.read(); // community
  final pdu = message.read();
  if (pdu.tag != 0xA2)
    throw FormatException('SNMP 响应 PDU 类型 0x${pdu.tag.toRadixString(16)}');
  final body = _BerReader(pdu.value);
  final requestId = _decodeInteger(body.read());
  final errorStatus = _decodeInteger(body.read());
  final errorIndex = _decodeInteger(body.read());
  if (errorStatus != 0)
    throw StateError('SNMP ErrorStatus=$errorStatus，ErrorIndex=$errorIndex');
  final list = body.read();
  if (list.tag != 0x30) throw const FormatException('SNMP VarBindList 格式错误');
  final variables = <SnmpVariable>[];
  final reader = _BerReader(list.value);
  while (!reader.done) {
    final variable = _BerReader(reader.read().value);
    final oid = _decodeOid(variable.read().value);
    final value = variable.read();
    variables.add(
      SnmpVariable(
        oid: oid,
        type: _typeName(value.tag),
        value: _valueText(value),
      ),
    );
  }
  return (requestId, variables);
}

class _BerValue {
  const _BerValue(this.tag, this.value);
  final int tag;
  final Uint8List value;
}

class _BerReader {
  _BerReader(this.bytes);
  final Uint8List bytes;
  int offset = 0;
  bool get done => offset >= bytes.length;
  _BerValue read() {
    if (offset >= bytes.length) throw const FormatException('BER 数据提前结束');
    final tag = bytes[offset++];
    if (offset >= bytes.length) throw const FormatException('BER 缺少长度');
    var length = bytes[offset++];
    if ((length & 0x80) != 0) {
      final count = length & 0x7F;
      if (count == 0 || count > 4 || offset + count > bytes.length)
        throw const FormatException('BER 长度字段无效');
      length = 0;
      for (var i = 0; i < count; i++) length = (length << 8) | bytes[offset++];
    }
    if (length < 0 || offset + length > bytes.length)
      throw const FormatException('BER Value 被截断');
    final value = Uint8List.fromList(bytes.sublist(offset, offset + length));
    offset += length;
    return _BerValue(tag, value);
  }
}

Uint8List _sequence(List<Uint8List> values) => _tlv(0x30, _concat(values));
Uint8List _concat(List<Uint8List> values) {
  final builder = BytesBuilder(copy: false);
  for (final value in values) builder.add(value);
  return builder.takeBytes();
}

Uint8List _tlv(int tag, Uint8List value) =>
    Uint8List.fromList([tag, ..._length(value.length), ...value]);
List<int> _length(int value) {
  if (value < 128) return [value];
  final bytes = <int>[];
  var remaining = value;
  while (remaining > 0) {
    bytes.insert(0, remaining & 0xFF);
    remaining >>= 8;
  }
  return [0x80 | bytes.length, ...bytes];
}

Uint8List _integer(int value) {
  var bytes = <int>[];
  var current = value;
  do {
    bytes.insert(0, current & 0xFF);
    current >>= 8;
  } while (current > 0);
  if ((bytes.first & 0x80) != 0) bytes.insert(0, 0);
  return _tlv(0x02, Uint8List.fromList(bytes));
}

int _decodeInteger(_BerValue value) {
  if (value.value.isEmpty) return 0;
  var result = 0;
  for (final byte in value.value) result = (result << 8) | byte;
  return result;
}

Uint8List _encodeOid(String value) {
  final parts = _normalizeOid(
    value,
  ).split('.').where((e) => e.isNotEmpty).map(int.parse).toList();
  if (parts.length < 2 ||
      parts.first < 0 ||
      parts.first > 2 ||
      parts[1] < 0 ||
      (parts.first < 2 && parts[1] > 39))
    throw FormatException('OID 无效：$value');
  final output = <int>[];
  void component(int number) {
    if (number < 0) throw FormatException('OID 无效：$value');
    final encoded = <int>[number & 0x7F];
    var current = number >> 7;
    while (current > 0) {
      encoded.insert(0, 0x80 | (current & 0x7F));
      current >>= 7;
    }
    output.addAll(encoded);
  }

  component(parts[0] * 40 + parts[1]);
  for (final part in parts.skip(2)) component(part);
  return Uint8List.fromList(output);
}

String _decodeOid(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  final values = <int>[];
  var current = 0;
  for (final byte in bytes) {
    current = (current << 7) | (byte & 0x7F);
    if ((byte & 0x80) == 0) {
      values.add(current);
      current = 0;
    }
  }
  if (values.isEmpty) return '';
  final first = values.removeAt(0);
  final head = first < 40
      ? [0, first]
      : first < 80
      ? [1, first - 40]
      : [2, first - 80];
  return [...head, ...values].join('.');
}

String _typeName(int tag) => switch (tag) {
  0x02 => 'Integer',
  0x04 => 'OctetString',
  0x05 => 'Null',
  0x06 => 'OID',
  0x40 => 'IpAddress',
  0x41 => 'Counter32',
  0x42 => 'Gauge32',
  0x43 => 'TimeTicks',
  0x44 => 'Opaque',
  0x46 => 'Counter64',
  0x80 => 'NoSuchObject',
  0x81 => 'NoSuchInstance',
  0x82 => 'EndOfMibView',
  _ => 'Tag 0x${tag.toRadixString(16)}',
};
String _valueText(_BerValue value) {
  if (value.tag == 0x05) return 'null';
  if (value.tag == 0x06) return _decodeOid(value.value);
  if (value.tag == 0x40 && value.value.length == 4)
    return value.value.join('.');
  if ({0x02, 0x41, 0x42, 0x43, 0x46}.contains(value.tag))
    return '${_decodeInteger(value)}';
  if ({0x80, 0x81, 0x82}.contains(value.tag)) return _typeName(value.tag);
  if (value.tag == 0x04) {
    final text = utf8.decode(value.value, allowMalformed: true);
    if (!text.runes.any((r) => r < 9 || (r > 13 && r < 32))) return text;
  }
  return value.value
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join(' ')
      .toUpperCase();
}

String _normalizeOid(String value) =>
    value.trim().replaceFirst(RegExp(r'^\.+'), '');
int _compareOid(String left, String right) {
  final a = left.split('.').map(int.parse).toList();
  final b = right.split('.').map(int.parse).toList();
  for (var i = 0; i < min(a.length, b.length); i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return a.length.compareTo(b.length);
}

const commonSnmpOids = <String, String>{
  '1.3.6.1.2.1.1.1.0': 'sysDescr',
  '1.3.6.1.2.1.1.2.0': 'sysObjectID',
  '1.3.6.1.2.1.1.3.0': 'sysUpTime',
  '1.3.6.1.2.1.1.4.0': 'sysContact',
  '1.3.6.1.2.1.1.5.0': 'sysName',
  '1.3.6.1.2.1.1.6.0': 'sysLocation',
  '1.3.6.1.2.1.2.2.1': 'ifTable',
};

class _V3Engine {
  const _V3Engine(this.id, this.boots, this.time);
  final Uint8List id;
  final int boots;
  final int time;
}

class _V3Envelope {
  const _V3Envelope({
    required this.engineId,
    required this.engineBoots,
    required this.engineTime,
    required this.username,
    required this.authParameters,
    required this.privacyParameters,
    required this.messageData,
    required this.encrypted,
  });
  final Uint8List engineId;
  final int engineBoots;
  final int engineTime;
  final String username;
  final Uint8List authParameters;
  final Uint8List privacyParameters;
  final Uint8List messageData;
  final bool encrypted;
}

Uint8List _buildV3Discovery(int requestId) {
  final pdu = _buildPdu(
    requestId,
    const ['1.3.6.1.6.3.15.1.1.4.0'],
    SnmpOperation.get,
    0,
  );
  final scoped = _sequence([
    _tlv(0x04, Uint8List(0)),
    _tlv(0x04, Uint8List(0)),
    pdu,
  ]);
  final security = _sequence([
    _tlv(0x04, Uint8List(0)),
    _integer(0),
    _integer(0),
    _tlv(0x04, Uint8List(0)),
    _tlv(0x04, Uint8List(0)),
    _tlv(0x04, Uint8List(0)),
  ]);
  return _sequence([
    _integer(3),
    _sequence([
      _integer(requestId),
      _integer(65535),
      _tlv(0x04, Uint8List.fromList([0x04])),
      _integer(3),
    ]),
    _tlv(0x04, security),
    scoped,
  ]);
}

Uint8List _buildV3Request(
  _V3Engine engine,
  SnmpV3Credentials credentials,
  int requestId,
  List<String> oids,
  SnmpOperation operation,
  int maxRepetitions,
  Random random,
) {
  final auth = credentials.securityLevel != SnmpV3SecurityLevel.noAuthNoPriv;
  final privacy = credentials.securityLevel == SnmpV3SecurityLevel.authPriv;
  final authLength = credentials.authProtocol == SnmpV3AuthProtocol.sha256
      ? 24
      : 12;
  final salt = privacy
      ? Uint8List.fromList(List<int>.generate(8, (_) => random.nextInt(256)))
      : Uint8List(0);
  final pdu = _buildPdu(requestId, oids, operation, maxRepetitions);
  final scoped = _sequence([
    _tlv(0x04, engine.id),
    _tlv(0x04, Uint8List(0)),
    pdu,
  ]);
  Uint8List messageData = scoped;
  if (privacy) {
    final privacyKey = _localizedKey(
      credentials.privacyPassword,
      engine.id,
      credentials.authProtocol,
    );
    final iv = Uint8List(16);
    ByteData.sublistView(iv)
      ..setUint32(0, engine.boots, Endian.big)
      ..setUint32(4, engine.time, Endian.big);
    iv.setRange(8, 16, salt);
    messageData = _tlv(
      0x04,
      _aesCfb(scoped, privacyKey.sublist(0, 16), iv, true),
    );
  }
  final security = _sequence([
    _tlv(0x04, engine.id),
    _integer(engine.boots),
    _integer(engine.time),
    _tlv(0x04, Uint8List.fromList(utf8.encode(credentials.username))),
    _tlv(0x04, Uint8List(auth ? authLength : 0)),
    _tlv(0x04, salt),
  ]);
  var flags = 0x04;
  if (auth) flags |= 0x01;
  if (privacy) flags |= 0x02;
  final message = _sequence([
    _integer(3),
    _sequence([
      _integer(requestId),
      _integer(65535),
      _tlv(0x04, Uint8List.fromList([flags])),
      _integer(3),
    ]),
    _tlv(0x04, security),
    messageData,
  ]);
  if (!auth) return message;
  final offset = _findAuthOffset(message, Uint8List(authLength));
  if (offset < 0) throw StateError('无法定位 SNMPv3 Authentication Parameters');
  final key = _localizedKey(
    credentials.authPassword,
    engine.id,
    credentials.authProtocol,
  );
  final digest = Hmac(
    _hash(credentials.authProtocol),
    key,
  ).convert(message).bytes;
  message.setRange(offset, offset + authLength, digest.take(authLength));
  return message;
}

Uint8List _buildPdu(
  int requestId,
  List<String> oids,
  SnmpOperation operation,
  int maxRepetitions,
) {
  final variables = _sequence([
    for (final oid in oids)
      _sequence([_tlv(0x06, _encodeOid(oid)), _tlv(0x05, Uint8List(0))]),
  ]);
  final tag = switch (operation) {
    SnmpOperation.get => 0xA0,
    SnmpOperation.getNext => 0xA1,
    SnmpOperation.getBulk => 0xA5,
  };
  return _tlv(
    tag,
    _concat([
      _integer(requestId),
      _integer(0),
      _integer(
        operation == SnmpOperation.getBulk ? maxRepetitions.clamp(1, 100) : 0,
      ),
      variables,
    ]),
  );
}

_V3Envelope _decodeV3Envelope(Uint8List bytes) {
  final top = _BerReader(bytes).read();
  if (top.tag != 0x30) throw const FormatException('SNMPv3 响应不是 Sequence');
  final message = _BerReader(top.value);
  if (_decodeInteger(message.read()) != 3) {
    throw const FormatException('不是 SNMPv3 响应');
  }
  message.read(); // HeaderData
  final securityOctets = message.read();
  if (securityOctets.tag != 0x04) {
    throw const FormatException('SNMPv3 Security Parameters 格式错误');
  }
  final securityTop = _BerReader(securityOctets.value).read();
  final security = _BerReader(securityTop.value);
  final engineId = security.read().value;
  final engineBoots = _decodeInteger(security.read());
  final engineTime = _decodeInteger(security.read());
  final username = utf8.decode(security.read().value, allowMalformed: true);
  final authParameters = security.read().value;
  final privacyParameters = security.read().value;
  final data = message.read();
  return _V3Envelope(
    engineId: engineId,
    engineBoots: engineBoots,
    engineTime: engineTime,
    username: username,
    authParameters: authParameters,
    privacyParameters: privacyParameters,
    messageData: data.value,
    encrypted: data.tag == 0x04,
  );
}

(int, List<SnmpVariable>) _decodeV3Response(
  Uint8List bytes,
  SnmpV3Credentials credentials,
  _V3Engine expectedEngine,
) {
  final envelope = _decodeV3Envelope(bytes);
  if (!_constantEquals(envelope.engineId, expectedEngine.id)) {
    throw const FormatException('SNMPv3 Engine ID 在会话中发生变化');
  }
  if (credentials.securityLevel != SnmpV3SecurityLevel.noAuthNoPriv) {
    final authLength = envelope.authParameters.length;
    final offset = _findAuthOffset(bytes, envelope.authParameters);
    if (offset < 0 || authLength == 0) {
      throw const FormatException('SNMPv3 响应缺少认证摘要');
    }
    final unsigned = Uint8List.fromList(bytes)
      ..fillRange(offset, offset + authLength, 0);
    final key = _localizedKey(
      credentials.authPassword,
      expectedEngine.id,
      credentials.authProtocol,
    );
    final expected = Hmac(
      _hash(credentials.authProtocol),
      key,
    ).convert(unsigned).bytes.take(authLength).toList();
    if (!_constantEquals(envelope.authParameters, expected)) {
      throw const FormatException('SNMPv3 响应认证摘要校验失败');
    }
  }

  Uint8List scopedBytes;
  if (envelope.encrypted) {
    if (credentials.securityLevel != SnmpV3SecurityLevel.authPriv ||
        envelope.privacyParameters.length != 8) {
      throw const FormatException('SNMPv3 加密响应参数无效');
    }
    final privacyKey = _localizedKey(
      credentials.privacyPassword,
      expectedEngine.id,
      credentials.authProtocol,
    );
    final iv = Uint8List(16);
    ByteData.sublistView(iv)
      ..setUint32(0, envelope.engineBoots, Endian.big)
      ..setUint32(4, envelope.engineTime, Endian.big);
    iv.setRange(8, 16, envelope.privacyParameters);
    scopedBytes = _aesCfb(
      envelope.messageData,
      privacyKey.sublist(0, 16),
      iv,
      false,
    );
  } else {
    // The BER reader returns the contents of the plaintext ScopedPDU sequence.
    scopedBytes = _tlv(0x30, envelope.messageData);
  }
  final scopedTop = _BerReader(scopedBytes).read();
  if (scopedTop.tag != 0x30) {
    throw const FormatException('SNMPv3 ScopedPDU 格式错误');
  }
  final scoped = _BerReader(scopedTop.value);
  scoped.read(); // contextEngineID
  scoped.read(); // contextName
  final pdu = scoped.read();
  if (pdu.tag == 0xA8) {
    final report = _decodeResponsePdu(pdu);
    final detail = report.$2.isEmpty
        ? '未知 Report'
        : '${report.$2.first.oid}=${report.$2.first.value}';
    throw StateError('SNMPv3 Agent 返回 Report：$detail');
  }
  if (pdu.tag != 0xA2) {
    throw FormatException('SNMPv3 响应 PDU 类型 0x${pdu.tag.toRadixString(16)}');
  }
  return _decodeResponsePdu(pdu);
}

(int, List<SnmpVariable>) _decodeResponsePdu(_BerValue pdu) {
  final body = _BerReader(pdu.value);
  final requestId = _decodeInteger(body.read());
  final errorStatus = _decodeInteger(body.read());
  final errorIndex = _decodeInteger(body.read());
  if (errorStatus != 0) {
    throw StateError('SNMP ErrorStatus=$errorStatus，ErrorIndex=$errorIndex');
  }
  final list = body.read();
  if (list.tag != 0x30) throw const FormatException('SNMP VarBindList 格式错误');
  final variables = <SnmpVariable>[];
  final reader = _BerReader(list.value);
  while (!reader.done) {
    final variable = _BerReader(reader.read().value);
    final oid = _decodeOid(variable.read().value);
    final value = variable.read();
    variables.add(
      SnmpVariable(
        oid: oid,
        type: _typeName(value.tag),
        value: _valueText(value),
      ),
    );
  }
  return (requestId, variables);
}

Hash _hash(SnmpV3AuthProtocol protocol) => switch (protocol) {
  SnmpV3AuthProtocol.md5 => md5,
  SnmpV3AuthProtocol.sha1 => sha1,
  SnmpV3AuthProtocol.sha256 => sha256,
};

Uint8List _localizedKey(
  String password,
  Uint8List engineId,
  SnmpV3AuthProtocol protocol,
) {
  final pass = utf8.encode(password);
  if (pass.isEmpty) throw const FormatException('SNMPv3 密码不能为空');
  final repeated = Uint8List(1048576);
  for (var i = 0; i < repeated.length; i++) repeated[i] = pass[i % pass.length];
  final ku = _hash(protocol).convert(repeated).bytes;
  return Uint8List.fromList(
    _hash(protocol).convert([...ku, ...engineId, ...ku]).bytes,
  );
}

int _findAuthOffset(Uint8List message, List<int> auth) {
  if (auth.isEmpty || auth.length >= 128) return -1;
  for (var i = 0; i + auth.length + 4 <= message.length; i++) {
    if (message[i] != 0x04 || message[i + 1] != auth.length) continue;
    var equal = true;
    for (var j = 0; j < auth.length; j++) {
      if (message[i + 2 + j] != auth[j]) {
        equal = false;
        break;
      }
    }
    if (!equal) continue;
    final next = i + 2 + auth.length;
    if (next < message.length && message[next] == 0x04) return i + 2;
  }
  return -1;
}

Uint8List _aesCfb(Uint8List input, Uint8List key, Uint8List iv, bool encrypt) {
  final aes = AESEngine()..init(true, KeyParameter(key));
  final feedback = Uint8List.fromList(iv);
  final stream = Uint8List(16);
  final output = Uint8List(input.length);
  for (var offset = 0; offset < input.length; offset += 16) {
    aes.processBlock(feedback, 0, stream, 0);
    final count = min(16, input.length - offset);
    for (var i = 0; i < count; i++) {
      output[offset + i] = input[offset + i] ^ stream[i];
    }
    if (count == 16) {
      feedback.setRange(
        0,
        16,
        encrypt
            ? output.sublist(offset, offset + 16)
            : input.sublist(offset, offset + 16),
      );
    }
  }
  return output;
}

bool _constantEquals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var i = 0; i < left.length; i++) difference |= left[i] ^ right[i];
  return difference == 0;
}
