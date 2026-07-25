import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class SsdpDevice {
  const SsdpDevice({required this.address, required this.headers});
  final String address;
  final Map<String, String> headers;
  String? get usn => headers['usn'];
  String? get location => headers['location'];
  String? get server => headers['server'];
  String? get type => headers['st'];
}

class MdnsRecord {
  const MdnsRecord({
    required this.name,
    required this.type,
    required this.ttl,
    required this.value,
  });
  final String name;
  final String type;
  final int ttl;
  final String value;
}

class LocalDiscoveryService {
  static const _native = MethodChannel('nettools/native');

  Future<List<SsdpDevice>> discoverSsdp({
    Duration duration = const Duration(seconds: 4),
    String searchTarget = 'ssdp:all',
  }) async {
    await _acquireMulticastLock();
    late RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } on Object {
      await _releaseMulticastLock();
      rethrow;
    }
    final devices = <String, SsdpDevice>{};
    final query = utf8.encode(
      'M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 2\r\n'
      'ST: $searchTarget\r\n\r\n',
    );
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? packet;
      while ((packet = socket.receive()) != null) {
        final datagram = packet!;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        final headers = <String, String>{};
        for (final line in text.split(RegExp(r'\r?\n')).skip(1)) {
          final colon = line.indexOf(':');
          if (colon > 0)
            headers[line.substring(0, colon).trim().toLowerCase()] = line
                .substring(colon + 1)
                .trim();
        }
        final key =
            headers['usn'] ??
            headers['location'] ??
            '${datagram.address.address}:${datagram.port}';
        devices[key] = SsdpDevice(
          address: datagram.address.address,
          headers: headers,
        );
      }
    });
    try {
      final target = InternetAddress('239.255.255.250');
      for (var i = 0; i < 3; i++) {
        socket.send(query, target, 1900);
        if (i < 2)
          await Future<void>.delayed(const Duration(milliseconds: 180));
      }
      await Future<void>.delayed(duration);
    } finally {
      await subscription.cancel();
      socket.close();
      await _releaseMulticastLock();
    }
    return devices.values.toList()
      ..sort((a, b) => a.address.compareTo(b.address));
  }

  Future<List<MdnsRecord>> discoverMdns({
    Duration duration = const Duration(seconds: 4),
  }) async {
    await _acquireMulticastLock();
    late RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        5353,
        reuseAddress: true,
        reusePort: true,
      );
    } on Object {
      await _releaseMulticastLock();
      rethrow;
    }
    socket.joinMulticast(InternetAddress('224.0.0.251'));
    final records = <String, MdnsRecord>{};
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? packet;
      while ((packet = socket.receive()) != null) {
        for (final record in _parseMdns(Uint8List.fromList(packet!.data))) {
          records['${record.name}|${record.type}|${record.value}'] = record;
        }
      }
    });
    try {
      socket.send(
        _mdnsQuery('_services._dns-sd._udp.local'),
        InternetAddress('224.0.0.251'),
        5353,
      );
      await Future<void>.delayed(duration);
    } finally {
      await subscription.cancel();
      socket.close();
      await _releaseMulticastLock();
    }
    return records.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _acquireMulticastLock() => Platform.isAndroid
      ? _native.invokeMethod<void>('acquireMulticastLock')
      : Future<void>.value();

  Future<void> _releaseMulticastLock() => Platform.isAndroid
      ? _native.invokeMethod<void>('releaseMulticastLock')
      : Future<void>.value();

  Uint8List _mdnsQuery(String name) {
    final bytes = BytesBuilder()..add([0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
    for (final label in name.split('.')) {
      final encoded = utf8.encode(label);
      bytes.addByte(encoded.length);
      bytes.add(encoded);
    }
    bytes.add([0, 0, 12, 0, 1]);
    return bytes.takeBytes();
  }

  List<MdnsRecord> _parseMdns(Uint8List bytes) {
    if (bytes.length < 12) return const [];
    final data = ByteData.sublistView(bytes);
    final questionCount = data.getUint16(4);
    final recordCount =
        data.getUint16(6) + data.getUint16(8) + data.getUint16(10);
    var offset = 12;
    try {
      for (var i = 0; i < questionCount; i++) {
        offset = _readName(bytes, offset).$2 + 4;
      }
      final results = <MdnsRecord>[];
      for (var i = 0; i < recordCount; i++) {
        final nameResult = _readName(bytes, offset);
        offset = nameResult.$2;
        if (offset + 10 > bytes.length) break;
        final type = data.getUint16(offset);
        final ttl = data.getUint32(offset + 4);
        final length = data.getUint16(offset + 8);
        final valueOffset = offset + 10;
        if (valueOffset + length > bytes.length) break;
        final label = switch (type) {
          1 => 'A',
          12 => 'PTR',
          16 => 'TXT',
          28 => 'AAAA',
          33 => 'SRV',
          _ => 'TYPE$type',
        };
        String value;
        if (type == 1 && length == 4) {
          value = InternetAddress.fromRawAddress(
            bytes.sublist(valueOffset, valueOffset + 4),
          ).address;
        } else if (type == 28 && length == 16) {
          value = InternetAddress.fromRawAddress(
            bytes.sublist(valueOffset, valueOffset + 16),
          ).address;
        } else if (type == 12) {
          value = _readName(bytes, valueOffset).$1;
        } else if (type == 33 && length >= 6) {
          value =
              '${data.getUint16(valueOffset + 4)} · ${_readName(bytes, valueOffset + 6).$1}';
        } else if (type == 16) {
          final parts = <String>[];
          var cursor = valueOffset;
          while (cursor < valueOffset + length) {
            final size = bytes[cursor++];
            if (cursor + size > valueOffset + length) break;
            parts.add(
              utf8.decode(
                bytes.sublist(cursor, cursor + size),
                allowMalformed: true,
              ),
            );
            cursor += size;
          }
          value = parts.join(' · ');
        } else {
          value = '$length bytes';
        }
        results.add(
          MdnsRecord(name: nameResult.$1, type: label, ttl: ttl, value: value),
        );
        offset = valueOffset + length;
      }
      return results;
    } on Object {
      return const [];
    }
  }

  (String, int) _readName(Uint8List bytes, int start) {
    final labels = <String>[];
    var cursor = start;
    var next = start;
    var jumped = false;
    final visited = <int>{};
    while (cursor < bytes.length && visited.add(cursor)) {
      final length = bytes[cursor];
      if (length == 0) {
        if (!jumped) next = cursor + 1;
        break;
      }
      if ((length & 0xc0) == 0xc0) {
        if (cursor + 1 >= bytes.length)
          throw const FormatException('mDNS 指针截断');
        final pointer = ((length & 0x3f) << 8) | bytes[cursor + 1];
        if (!jumped) next = cursor + 2;
        cursor = pointer;
        jumped = true;
        continue;
      }
      final end = cursor + 1 + length;
      if (end > bytes.length) throw const FormatException('mDNS 名称截断');
      labels.add(
        utf8.decode(bytes.sublist(cursor + 1, end), allowMalformed: true),
      );
      cursor = end;
      if (!jumped) next = cursor;
    }
    return (labels.join('.'), next);
  }
}
