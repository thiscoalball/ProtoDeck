import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

enum DnsRecordType {
  a(1, 'A'),
  ns(2, 'NS'),
  cname(5, 'CNAME'),
  soa(6, 'SOA'),
  ptr(12, 'PTR'),
  mx(15, 'MX'),
  txt(16, 'TXT'),
  aaaa(28, 'AAAA'),
  srv(33, 'SRV'),
  caa(257, 'CAA');

  const DnsRecordType(this.code, this.label);
  final int code;
  final String label;
}

enum DnsTransport {
  system('系统'),
  udp('UDP'),
  tcp('TCP'),
  dot('DoT'),
  doh('DoH');

  const DnsTransport(this.label);
  final String label;
}

class DnsRecord {
  const DnsRecord({
    required this.name,
    required this.type,
    required this.ttl,
    required this.data,
    required this.section,
  });

  final String name;
  final String type;
  final int ttl;
  final String data;
  final String section;
}

class DnsLookupResult {
  const DnsLookupResult({
    required this.records,
    required this.elapsed,
    required this.server,
    required this.rcode,
    required this.truncated,
    this.error,
  });

  final List<DnsRecord> records;
  final Duration elapsed;
  final String server;
  final String rcode;
  final bool truncated;
  final String? error;
  bool get success => error == null && rcode == 'NOERROR';
}

class DnsService {
  Future<DnsLookupResult> lookup(
    String input, {
    DnsRecordType type = DnsRecordType.a,
    DnsTransport transport = DnsTransport.udp,
    String server = '223.5.5.5',
    int port = 53,
    Uri? dohEndpoint,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final watch = Stopwatch()..start();
    final name = _queryName(input.trim(), type);
    if (name.isEmpty) {
      return _error(watch, server, '查询目标不能为空');
    }
    try {
      if (transport == DnsTransport.system) {
        if (type != DnsRecordType.a && type != DnsRecordType.aaaa) {
          return _error(
            watch,
            '系统 DNS',
            '系统解析仅支持 A/AAAA，请选择 UDP、TCP、DoT 或 DoH',
          );
        }
        final addresses = await InternetAddress.lookup(name).timeout(timeout);
        final expected = type == DnsRecordType.a
            ? InternetAddressType.IPv4
            : InternetAddressType.IPv6;
        final records = addresses
            .where((address) => address.type == expected)
            .map(
              (address) => DnsRecord(
                name: name,
                type: type.label,
                ttl: 0,
                data: address.address,
                section: 'Answer',
              ),
            )
            .toList();
        watch.stop();
        return DnsLookupResult(
          records: records,
          elapsed: watch.elapsed,
          server: '系统 DNS',
          rcode: 'NOERROR',
          truncated: false,
        );
      }

      final id = Random.secure().nextInt(0xffff);
      final query = _buildQuery(id, name, type.code);
      Uint8List response;
      var usedServer = server;
      if (transport == DnsTransport.udp) {
        response = await _udp(server, port, query, timeout);
        final parsed = _parseResponse(response, id);
        if (parsed.truncated) {
          response = await _tcp(server, port, query, timeout, tls: false);
          usedServer = '$server:$port（UDP 截断后 TCP）';
        }
      } else if (transport == DnsTransport.tcp) {
        response = await _tcp(server, port, query, timeout, tls: false);
      } else if (transport == DnsTransport.dot) {
        final dotPort = port == 53 ? 853 : port;
        response = await _tcp(server, dotPort, query, timeout, tls: true);
        usedServer = '$server:$dotPort';
      } else {
        final endpoint =
            dohEndpoint ?? Uri.parse('https://dns.alidns.com/dns-query');
        response = await _doh(endpoint, query, timeout);
        usedServer = endpoint.toString();
      }
      final parsed = _parseResponse(response, id);
      watch.stop();
      return DnsLookupResult(
        records: parsed.records,
        elapsed: watch.elapsed,
        server: usedServer,
        rcode: parsed.rcode,
        truncated: parsed.truncated,
        error: parsed.rcode == 'NOERROR' ? null : 'DNS 返回 ${parsed.rcode}',
      );
    } on Object catch (error) {
      return _error(watch, server, '$error');
    }
  }

  DnsLookupResult _error(Stopwatch watch, String server, String message) {
    watch.stop();
    return DnsLookupResult(
      records: const [],
      elapsed: watch.elapsed,
      server: server,
      rcode: 'ERROR',
      truncated: false,
      error: message,
    );
  }

  String _queryName(String input, DnsRecordType type) {
    if (type != DnsRecordType.ptr)
      return input.replaceFirst(RegExp(r'\.$'), '');
    final address = InternetAddress.tryParse(input);
    if (address == null) return input.replaceFirst(RegExp(r'\.$'), '');
    if (address.type == InternetAddressType.IPv4) {
      return '${address.address.split('.').reversed.join('.')}.in-addr.arpa';
    }
    final nibbles = address.rawAddress
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .split('')
        .reversed
        .join('.');
    return '$nibbles.ip6.arpa';
  }

  Uint8List _buildQuery(int id, String name, int type) {
    final builder = BytesBuilder();
    builder.add([
      id >> 8,
      id & 0xff,
      0x01,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);
    for (final label in name.split('.')) {
      final bytes = ascii.encode(label);
      if (bytes.isEmpty || bytes.length > 63) {
        throw const FormatException('域名标签长度无效');
      }
      builder.addByte(bytes.length);
      builder.add(bytes);
    }
    builder.addByte(0);
    builder.add([type >> 8, type & 0xff, 0, 1]);
    return builder.takeBytes();
  }

  Future<Uint8List> _udp(
    String server,
    int port,
    Uint8List query,
    Duration timeout,
  ) async {
    final target = (await InternetAddress.lookup(
      server,
    ).timeout(timeout)).first;
    final socket = await RawDatagramSocket.bind(
      target.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    final completer = Completer<Uint8List>();
    late StreamSubscription<RawSocketEvent> subscription;
    try {
      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final datagram = socket.receive();
        if (datagram != null) {
          completer.complete(Uint8List.fromList(datagram.data));
        }
      }, onError: completer.completeError);
      socket.send(query, target, port);
      return await completer.future.timeout(timeout);
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }

  Future<Uint8List> _tcp(
    String server,
    int port,
    Uint8List query,
    Duration timeout, {
    required bool tls,
  }) async {
    final Socket socket = tls
        ? await SecureSocket.connect(server, port, timeout: timeout)
        : await Socket.connect(server, port, timeout: timeout);
    final completer = Completer<Uint8List>();
    final buffer = <int>[];
    int? expected;
    late StreamSubscription<List<int>> subscription;
    subscription = socket.listen(
      (chunk) {
        buffer.addAll(chunk);
        if (expected == null && buffer.length >= 2) {
          expected = (buffer[0] << 8) | buffer[1];
        }
        if (expected != null &&
            buffer.length >= expected! + 2 &&
            !completer.isCompleted) {
          completer.complete(
            Uint8List.fromList(buffer.sublist(2, expected! + 2)),
          );
        }
      },
      onError: completer.completeError,
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(const SocketException('DNS TCP 连接提前关闭'));
        }
      },
    );
    try {
      socket.add([query.length >> 8, query.length & 0xff, ...query]);
      await socket.flush();
      return await completer.future.timeout(timeout);
    } finally {
      await subscription.cancel();
      socket.destroy();
    }
  }

  Future<Uint8List> _doh(
    Uri endpoint,
    Uint8List query,
    Duration timeout,
  ) async {
    final response = await http
        .post(
          endpoint,
          headers: const {
            'accept': 'application/dns-message',
            'content-type': 'application/dns-message',
          },
          body: query,
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw HttpException('DoH HTTP ${response.statusCode}', uri: endpoint);
    }
    return Uint8List.fromList(response.bodyBytes);
  }

  _ParsedDnsResponse _parseResponse(Uint8List bytes, int expectedId) {
    if (bytes.length < 12) throw const FormatException('DNS 响应过短');
    final data = ByteData.sublistView(bytes);
    final id = data.getUint16(0);
    if (id != expectedId) throw const FormatException('DNS 响应 ID 不匹配');
    final flags = data.getUint16(2);
    final questions = data.getUint16(4);
    final answers = data.getUint16(6);
    final authorities = data.getUint16(8);
    final additionals = data.getUint16(10);
    var offset = 12;
    for (var index = 0; index < questions; index++) {
      final name = _readName(bytes, offset);
      offset = name.nextOffset + 4;
      if (offset > bytes.length) throw const FormatException('DNS Question 越界');
    }
    final records = <DnsRecord>[];
    for (final section in [
      ('Answer', answers),
      ('Authority', authorities),
      ('Additional', additionals),
    ]) {
      for (var index = 0; index < section.$2; index++) {
        final parsed = _readRecord(bytes, offset, section.$1);
        records.add(parsed.record);
        offset = parsed.nextOffset;
      }
    }
    return _ParsedDnsResponse(
      records: records,
      rcode: _rcodeName(flags & 0x0f),
      truncated: flags & 0x0200 != 0,
    );
  }

  _RecordRead _readRecord(Uint8List bytes, int offset, String section) {
    final owner = _readName(bytes, offset);
    offset = owner.nextOffset;
    if (offset + 10 > bytes.length)
      throw const FormatException('DNS Record 越界');
    final view = ByteData.sublistView(bytes);
    final type = view.getUint16(offset);
    final ttl = view.getUint32(offset + 4);
    final length = view.getUint16(offset + 8);
    final rdataOffset = offset + 10;
    final end = rdataOffset + length;
    if (end > bytes.length) throw const FormatException('DNS RDATA 越界');
    final value = _rdata(bytes, type, rdataOffset, length);
    return _RecordRead(
      DnsRecord(
        name: owner.value,
        type: _typeName(type),
        ttl: ttl,
        data: value,
        section: section,
      ),
      end,
    );
  }

  String _rdata(Uint8List bytes, int type, int offset, int length) {
    final view = ByteData.sublistView(bytes);
    if (type == 1 && length == 4) {
      return bytes.sublist(offset, offset + 4).join('.');
    }
    if (type == 28 && length == 16) {
      final groups = <String>[];
      for (var index = 0; index < 16; index += 2) {
        groups.add(view.getUint16(offset + index).toRadixString(16));
      }
      return InternetAddress(groups.join(':')).address;
    }
    if (type == 2 || type == 5 || type == 12) {
      return _readName(bytes, offset).value;
    }
    if (type == 15) {
      return '${view.getUint16(offset)} ${_readName(bytes, offset + 2).value}';
    }
    if (type == 16) {
      final values = <String>[];
      var cursor = offset;
      final end = offset + length;
      while (cursor < end) {
        final size = bytes[cursor++];
        if (cursor + size > end) break;
        values.add(
          utf8.decode(
            bytes.sublist(cursor, cursor + size),
            allowMalformed: true,
          ),
        );
        cursor += size;
      }
      return values.map((value) => '"$value"').join(' ');
    }
    if (type == 6) {
      final mname = _readName(bytes, offset);
      final rname = _readName(bytes, mname.nextOffset);
      final cursor = rname.nextOffset;
      if (cursor + 20 <= offset + length) {
        return '${mname.value} ${rname.value} ${view.getUint32(cursor)} '
            '${view.getUint32(cursor + 4)} ${view.getUint32(cursor + 8)} '
            '${view.getUint32(cursor + 12)} ${view.getUint32(cursor + 16)}';
      }
    }
    if (type == 33 && length >= 7) {
      return '${view.getUint16(offset)} ${view.getUint16(offset + 2)} '
          '${view.getUint16(offset + 4)} ${_readName(bytes, offset + 6).value}';
    }
    if (type == 257 && length >= 2) {
      final flags = bytes[offset];
      final tagLength = bytes[offset + 1];
      if (tagLength + 2 <= length) {
        final tag = ascii.decode(
          bytes.sublist(offset + 2, offset + 2 + tagLength),
        );
        final value = utf8.decode(
          bytes.sublist(offset + 2 + tagLength, offset + length),
          allowMalformed: true,
        );
        return '$flags $tag "$value"';
      }
    }
    return bytes
        .sublist(offset, offset + length)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  _NameRead _readName(Uint8List bytes, int offset) {
    final labels = <String>[];
    var cursor = offset;
    var nextOffset = offset;
    var jumped = false;
    final visited = <int>{};
    while (true) {
      if (cursor >= bytes.length || !visited.add(cursor)) {
        throw const FormatException('DNS 名称压缩指针无效');
      }
      final length = bytes[cursor];
      if (length == 0) {
        if (!jumped) nextOffset = cursor + 1;
        break;
      }
      if (length & 0xc0 == 0xc0) {
        if (cursor + 1 >= bytes.length) throw const FormatException('DNS 指针越界');
        final pointer = ((length & 0x3f) << 8) | bytes[cursor + 1];
        if (!jumped) nextOffset = cursor + 2;
        cursor = pointer;
        jumped = true;
        continue;
      }
      if (length > 63 || cursor + 1 + length > bytes.length) {
        throw const FormatException('DNS 标签越界');
      }
      labels.add(ascii.decode(bytes.sublist(cursor + 1, cursor + 1 + length)));
      cursor += length + 1;
      if (!jumped) nextOffset = cursor;
    }
    return _NameRead(labels.join('.'), nextOffset);
  }

  String _typeName(int type) {
    for (final value in DnsRecordType.values) {
      if (value.code == type) return value.label;
    }
    return 'TYPE$type';
  }

  String _rcodeName(int code) => switch (code) {
    0 => 'NOERROR',
    1 => 'FORMERR',
    2 => 'SERVFAIL',
    3 => 'NXDOMAIN',
    4 => 'NOTIMP',
    5 => 'REFUSED',
    _ => 'RCODE$code',
  };
}

class _NameRead {
  const _NameRead(this.value, this.nextOffset);
  final String value;
  final int nextOffset;
}

class _RecordRead {
  const _RecordRead(this.record, this.nextOffset);
  final DnsRecord record;
  final int nextOffset;
}

class _ParsedDnsResponse {
  const _ParsedDnsResponse({
    required this.records,
    required this.rcode,
    required this.truncated,
  });
  final List<DnsRecord> records;
  final String rcode;
  final bool truncated;
}
