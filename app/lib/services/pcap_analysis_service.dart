import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class CaptureAnalysis {
  const CaptureAnalysis({
    required this.path,
    required this.format,
    required this.fileSize,
    required this.startedAt,
    required this.endedAt,
    required this.packetCount,
    required this.byteCount,
    required this.protocolBytes,
    required this.protocolHierarchy,
    required this.endpoints,
    required this.ioBuckets,
    required this.flows,
    required this.packets,
    required this.truncatedPacketList,
  });

  final String path;
  final String format;
  final int fileSize;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int packetCount;
  final int byteCount;
  final Map<String, int> protocolBytes;
  final List<CaptureProtocolStat> protocolHierarchy;
  final Map<String, int> endpoints;
  final List<CaptureIoBucket> ioBuckets;
  final List<CaptureFlow> flows;
  final List<CapturePacket> packets;
  final bool truncatedPacketList;

  Duration? get duration => startedAt == null || endedAt == null
      ? null
      : endedAt!.difference(startedAt!);
}

class CaptureProtocolStat {
  const CaptureProtocolStat({
    required this.path,
    required this.packetCount,
    required this.byteCount,
  });

  final List<String> path;
  final int packetCount;
  final int byteCount;
}

class CaptureIoBucket {
  const CaptureIoBucket({
    required this.startedAt,
    required this.packetCount,
    required this.byteCount,
  });

  final DateTime startedAt;
  final int packetCount;
  final int byteCount;
}

class CaptureFlow {
  const CaptureFlow({
    required this.protocol,
    required this.endpointA,
    required this.endpointB,
    required this.packetCount,
    required this.byteCount,
    required this.bytesAToB,
    required this.bytesBToA,
    required this.firstSeen,
    required this.lastSeen,
    required this.details,
  });

  final String protocol;
  final String endpointA;
  final String endpointB;
  final int packetCount;
  final int byteCount;
  final int bytesAToB;
  final int bytesBToA;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final List<String> details;

  Duration get duration => lastSeen.difference(firstSeen);
}

class CapturePacket {
  const CapturePacket({
    required this.number,
    required this.timestamp,
    required this.capturedLength,
    required this.originalLength,
    required this.linkType,
    required this.networkProtocol,
    required this.transportProtocol,
    required this.applicationProtocol,
    required this.applicationDetail,
    required this.source,
    required this.destination,
    required this.sourcePort,
    required this.destinationPort,
    required this.summary,
    required this.bytes,
  });

  final int number;
  final DateTime timestamp;
  final int capturedLength;
  final int originalLength;
  final int linkType;
  final String networkProtocol;
  final String transportProtocol;
  final String applicationProtocol;
  final String applicationDetail;
  final String source;
  final String destination;
  final int? sourcePort;
  final int? destinationPort;
  final String summary;
  final Uint8List bytes;

  String get protocol => applicationProtocol != 'Unknown'
      ? applicationProtocol
      : transportProtocol != 'Unknown'
      ? transportProtocol
      : networkProtocol;

  Map<String, Object?> toJson() => {
    'number': number,
    'timestamp': timestamp.toIso8601String(),
    'capturedLength': capturedLength,
    'originalLength': originalLength,
    'linkType': linkType,
    'networkProtocol': networkProtocol,
    'transportProtocol': transportProtocol,
    'applicationProtocol': applicationProtocol,
    if (applicationDetail.isNotEmpty) 'applicationDetail': applicationDetail,
    'source': source,
    if (sourcePort != null) 'sourcePort': sourcePort,
    'destination': destination,
    if (destinationPort != null) 'destinationPort': destinationPort,
    'summary': summary,
  };
}

class PcapAnalysisService {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Future<CaptureAnalysis> analyze(
    String path, {
    void Function(int bytesRead, int fileSize)? onProgress,
    int maxRetainedPackets = 50000,
  }) async {
    _cancelled = false;
    final file = File(path);
    final size = await file.length();
    final reader = await file.open();
    try {
      final magicBytes = await reader.read(4);
      if (magicBytes.length != 4) throw const FormatException('抓包文件头不完整');
      await reader.setPosition(0);
      final magic = ByteData.sublistView(Uint8List.fromList(magicBytes));
      if (magic.getUint32(0, Endian.big) == 0x0A0D0D0A) {
        return await _readPcapNg(
          reader,
          path,
          size,
          onProgress,
          maxRetainedPackets,
        );
      }
      return await _readClassic(
        reader,
        path,
        size,
        onProgress,
        maxRetainedPackets,
      );
    } finally {
      await reader.close();
    }
  }

  Future<CaptureAnalysis> _readClassic(
    RandomAccessFile reader,
    String path,
    int fileSize,
    void Function(int, int)? onProgress,
    int maxRetainedPackets,
  ) async {
    final global = await _readExact(reader, 24, 'PCAP 全局头');
    final magic = ByteData.sublistView(global).getUint32(0, Endian.big);
    final (endian, nanos) = switch (magic) {
      0xA1B2C3D4 => (Endian.big, false),
      0xD4C3B2A1 => (Endian.little, false),
      0xA1B23C4D => (Endian.big, true),
      0x4D3CB2A1 => (Endian.little, true),
      _ => throw FormatException(
        '不支持的 PCAP Magic 0x${magic.toRadixString(16)}',
      ),
    };
    final header = ByteData.sublistView(global);
    final linkType = header.getUint32(20, endian);
    final accumulator = _CaptureAccumulator(
      path,
      'PCAP',
      fileSize,
      maxRetainedPackets,
    );
    var position = 24;
    while (position < fileSize) {
      _checkCancelled();
      final record = await reader.read(16);
      if (record.isEmpty) break;
      if (record.length != 16)
        throw FormatException('PCAP 数据包头在偏移 $position 处被截断');
      position += 16;
      final data = ByteData.sublistView(Uint8List.fromList(record));
      final seconds = data.getUint32(0, endian);
      final fraction = data.getUint32(4, endian);
      final included = data.getUint32(8, endian);
      final original = data.getUint32(12, endian);
      if (included > 16 * 1024 * 1024 || position + included > fileSize) {
        throw FormatException('PCAP 数据包长度异常（偏移 $position，长度 $included）');
      }
      final bytes = await _readExact(reader, included, 'PCAP 数据包');
      position += included;
      final micros = nanos ? fraction ~/ 1000 : fraction;
      accumulator.add(
        _decodePacket(
          accumulator.packetCount + 1,
          DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          ).add(Duration(microseconds: micros)),
          linkType,
          bytes,
          original,
        ),
      );
      if (accumulator.packetCount % 128 == 0) {
        onProgress?.call(position, fileSize);
        await Future<void>.delayed(Duration.zero);
      }
    }
    onProgress?.call(fileSize, fileSize);
    return accumulator.finish();
  }

  Future<CaptureAnalysis> _readPcapNg(
    RandomAccessFile reader,
    String path,
    int fileSize,
    void Function(int, int)? onProgress,
    int maxRetainedPackets,
  ) async {
    final accumulator = _CaptureAccumulator(
      path,
      'PCAPNG',
      fileSize,
      maxRetainedPackets,
    );
    final interfaces = <int>[];
    var endian = Endian.little;
    var position = 0;
    while (position < fileSize) {
      _checkCancelled();
      final prefixBytes = await reader.read(12);
      if (prefixBytes.isEmpty) break;
      if (prefixBytes.length != 12)
        throw FormatException('PCAPNG 块头在偏移 $position 处被截断');
      final prefix = ByteData.sublistView(Uint8List.fromList(prefixBytes));
      final typeBig = prefix.getUint32(0, Endian.big);
      if (typeBig == 0x0A0D0D0A) {
        final byteOrderMagic = prefix.getUint32(8, Endian.big);
        endian = switch (byteOrderMagic) {
          0x1A2B3C4D => Endian.big,
          0x4D3C2B1A => Endian.little,
          _ => throw FormatException('PCAPNG 字节序标记无效（偏移 $position）'),
        };
        interfaces.clear();
      }
      final type = prefix.getUint32(0, endian);
      final totalLength = prefix.getUint32(4, endian);
      if (totalLength < 12 ||
          totalLength > 32 * 1024 * 1024 ||
          position + totalLength > fileSize) {
        throw FormatException('PCAPNG 块长度异常（偏移 $position，长度 $totalLength）');
      }
      final remaining = await _readExact(reader, totalLength - 12, 'PCAPNG 块');
      final block = Uint8List(totalLength);
      block.setRange(0, 12, prefixBytes);
      block.setRange(12, totalLength, remaining);
      final data = ByteData.sublistView(block);
      final trailing = data.getUint32(totalLength - 4, endian);
      if (trailing != totalLength)
        throw FormatException('PCAPNG 块尾长度不匹配（偏移 $position）');

      if (type == 0x00000001 && totalLength >= 20) {
        interfaces.add(data.getUint16(8, endian));
      } else if (type == 0x00000006 && totalLength >= 32) {
        final interfaceId = data.getUint32(8, endian);
        final timeHigh = data.getUint32(12, endian);
        final timeLow = data.getUint32(16, endian);
        final capturedLength = data.getUint32(20, endian);
        final originalLength = data.getUint32(24, endian);
        if (28 + capturedLength > totalLength - 4) {
          throw FormatException('PCAPNG 数据包内容被截断（偏移 $position）');
        }
        final timestampMicros = (timeHigh << 32) | timeLow;
        final bytes = Uint8List.sublistView(block, 28, 28 + capturedLength);
        accumulator.add(
          _decodePacket(
            accumulator.packetCount + 1,
            DateTime.fromMicrosecondsSinceEpoch(timestampMicros, isUtc: true),
            interfaceId < interfaces.length ? interfaces[interfaceId] : -1,
            Uint8List.fromList(bytes),
            originalLength,
          ),
        );
      }
      position += totalLength;
      if (accumulator.packetCount % 128 == 0) {
        onProgress?.call(position, fileSize);
        await Future<void>.delayed(Duration.zero);
      }
    }
    onProgress?.call(fileSize, fileSize);
    return accumulator.finish();
  }

  void _checkCancelled() {
    if (_cancelled) throw const PcapAnalysisCancelled();
  }
}

class PcapAnalysisCancelled implements Exception {
  const PcapAnalysisCancelled();
  @override
  String toString() => '抓包解析已取消';
}

class _CaptureAccumulator {
  _CaptureAccumulator(this.path, this.format, this.fileSize, this.maxRetained);
  final String path;
  final String format;
  final int fileSize;
  final int maxRetained;
  final packets = <CapturePacket>[];
  final protocolBytes = <String, int>{};
  final protocolHierarchy = <String, _ProtocolCounter>{};
  final endpoints = <String, int>{};
  final ioBuckets = <int, _ProtocolCounter>{};
  final flows = <String, _MutableCaptureFlow>{};
  var packetCount = 0;
  var byteCount = 0;
  DateTime? startedAt;
  DateTime? endedAt;

  void add(CapturePacket packet) {
    packetCount++;
    byteCount += packet.originalLength;
    startedAt ??= packet.timestamp;
    endedAt = packet.timestamp;
    protocolBytes.update(
      packet.protocol,
      (value) => value + packet.originalLength,
      ifAbsent: () => packet.originalLength,
    );
    final protocolPath = <String>[
      if (packet.networkProtocol != 'Unknown') packet.networkProtocol,
      if (packet.transportProtocol != 'Unknown') packet.transportProtocol,
      if (packet.applicationProtocol != 'Unknown') packet.applicationProtocol,
    ];
    for (var depth = 1; depth <= protocolPath.length; depth++) {
      final path = protocolPath.take(depth).join('/');
      protocolHierarchy.putIfAbsent(path, _ProtocolCounter.new).add(packet);
    }
    final second = packet.timestamp.millisecondsSinceEpoch ~/ 1000;
    ioBuckets.putIfAbsent(second, _ProtocolCounter.new).add(packet);
    for (final endpoint in [packet.source, packet.destination]) {
      if (endpoint.isNotEmpty) {
        endpoints.update(
          endpoint,
          (value) => value + packet.originalLength,
          ifAbsent: () => packet.originalLength,
        );
      }
    }
    if (packet.source.isNotEmpty && packet.destination.isNotEmpty) {
      final source = _packetEndpoint(packet.source, packet.sourcePort);
      final destination = _packetEndpoint(
        packet.destination,
        packet.destinationPort,
      );
      final sourceIsA = source.compareTo(destination) <= 0;
      final endpointA = sourceIsA ? source : destination;
      final endpointB = sourceIsA ? destination : source;
      final key = '${packet.transportProtocol}|$endpointA|$endpointB';
      final flow = flows.putIfAbsent(
        key,
        () => _MutableCaptureFlow(
          protocol: packet.protocol,
          endpointA: endpointA,
          endpointB: endpointB,
          firstSeen: packet.timestamp,
        ),
      );
      flow.add(packet, sourceIsA: sourceIsA);
    }
    if (packets.length < maxRetained) packets.add(packet);
  }

  CaptureAnalysis finish() => CaptureAnalysis(
    path: path,
    format: format,
    fileSize: fileSize,
    startedAt: startedAt,
    endedAt: endedAt,
    packetCount: packetCount,
    byteCount: byteCount,
    protocolBytes: Map.unmodifiable(protocolBytes),
    protocolHierarchy: List.unmodifiable(
      protocolHierarchy.entries
          .map(
            (entry) => CaptureProtocolStat(
              path: List.unmodifiable(entry.key.split('/')),
              packetCount: entry.value.packetCount,
              byteCount: entry.value.byteCount,
            ),
          )
          .toList()
        ..sort((left, right) {
          final depth = left.path.length.compareTo(right.path.length);
          if (depth != 0) return depth;
          return right.byteCount.compareTo(left.byteCount);
        }),
    ),
    endpoints: Map.unmodifiable(endpoints),
    ioBuckets: List.unmodifiable(
      ioBuckets.entries
          .map(
            (entry) => CaptureIoBucket(
              startedAt: DateTime.fromMillisecondsSinceEpoch(
                entry.key * 1000,
                isUtc: true,
              ),
              packetCount: entry.value.packetCount,
              byteCount: entry.value.byteCount,
            ),
          )
          .toList()
        ..sort((left, right) => left.startedAt.compareTo(right.startedAt)),
    ),
    flows: List.unmodifiable(
      flows.values.map((flow) => flow.finish()).toList()
        ..sort((left, right) => right.byteCount.compareTo(left.byteCount)),
    ),
    packets: List.unmodifiable(packets),
    truncatedPacketList: packetCount > packets.length,
  );
}

class _ProtocolCounter {
  int packetCount = 0;
  int byteCount = 0;

  void add(CapturePacket packet) {
    packetCount++;
    byteCount += packet.originalLength;
  }
}

String _packetEndpoint(String address, int? port) {
  if (port == null) return address;
  return address.contains(':') ? '[$address]:$port' : '$address:$port';
}

class _MutableCaptureFlow {
  _MutableCaptureFlow({
    required this.protocol,
    required this.endpointA,
    required this.endpointB,
    required this.firstSeen,
  });

  final String protocol;
  final String endpointA;
  final String endpointB;
  final DateTime firstSeen;
  DateTime? lastSeen;
  int packetCount = 0;
  int byteCount = 0;
  int bytesAToB = 0;
  int bytesBToA = 0;
  final details = <String>{};

  void add(CapturePacket packet, {required bool sourceIsA}) {
    packetCount++;
    byteCount += packet.originalLength;
    if (sourceIsA) {
      bytesAToB += packet.originalLength;
    } else {
      bytesBToA += packet.originalLength;
    }
    lastSeen = packet.timestamp;
    if (packet.applicationDetail.isNotEmpty && details.length < 8) {
      details.add(packet.applicationDetail);
    }
  }

  CaptureFlow finish() => CaptureFlow(
    protocol: protocol,
    endpointA: endpointA,
    endpointB: endpointB,
    packetCount: packetCount,
    byteCount: byteCount,
    bytesAToB: bytesAToB,
    bytesBToA: bytesBToA,
    firstSeen: firstSeen,
    lastSeen: lastSeen ?? firstSeen,
    details: List.unmodifiable(details),
  );
}

CapturePacket _decodePacket(
  int number,
  DateTime timestamp,
  int linkType,
  Uint8List bytes,
  int originalLength,
) {
  var offset = 0;
  var etherType = 0;
  if (linkType == 1 && bytes.length >= 14) {
    etherType = (bytes[12] << 8) | bytes[13];
    offset = 14;
    while ((etherType == 0x8100 || etherType == 0x88A8) &&
        bytes.length >= offset + 4) {
      etherType = (bytes[offset + 2] << 8) | bytes[offset + 3];
      offset += 4;
    }
  } else if (linkType == 101) {
    offset = 0;
    etherType = bytes.isEmpty ? 0 : (bytes[0] >> 4 == 6 ? 0x86DD : 0x0800);
  } else if (linkType == 113 && bytes.length >= 16) {
    etherType = (bytes[14] << 8) | bytes[15];
    offset = 16;
  } else if (linkType == 276 && bytes.length >= 20) {
    etherType = (bytes[0] << 8) | bytes[1];
    offset = 20;
  }

  var network = 'Unknown';
  var transport = 'Unknown';
  var application = 'Unknown';
  var applicationDetail = '';
  var source = '';
  var destination = '';
  int? sourcePort;
  int? destinationPort;
  var payloadOffset = offset;
  var protocolNumber = -1;

  if (etherType == 0x0806) {
    network = 'ARP';
  } else if (etherType == 0x0800 && bytes.length >= offset + 20) {
    network = 'IPv4';
    final ihl = (bytes[offset] & 0x0F) * 4;
    protocolNumber = bytes[offset + 9];
    source = _ipv4(bytes, offset + 12);
    destination = _ipv4(bytes, offset + 16);
    payloadOffset = offset + ihl;
  } else if (etherType == 0x86DD && bytes.length >= offset + 40) {
    network = 'IPv6';
    protocolNumber = bytes[offset + 6];
    source = _ipv6(bytes, offset + 8);
    destination = _ipv6(bytes, offset + 24);
    payloadOffset = offset + 40;
  }

  if ((protocolNumber == 6 || protocolNumber == 17) &&
      bytes.length >= payloadOffset + 4) {
    transport = protocolNumber == 6 ? 'TCP' : 'UDP';
    sourcePort = (bytes[payloadOffset] << 8) | bytes[payloadOffset + 1];
    destinationPort =
        (bytes[payloadOffset + 2] << 8) | bytes[payloadOffset + 3];
    application = _applicationProtocol(sourcePort, destinationPort, transport);
    final applicationPayloadOffset = protocolNumber == 17
        ? payloadOffset + 8
        : bytes.length >= payloadOffset + 13
        ? payloadOffset + ((bytes[payloadOffset + 12] >> 4) * 4)
        : bytes.length;
    if (applicationPayloadOffset <= bytes.length) {
      applicationDetail = _applicationDetail(
        application,
        bytes,
        applicationPayloadOffset,
      );
    }
  } else if (protocolNumber == 1) {
    transport = 'ICMP';
  } else if (protocolNumber == 58) {
    transport = 'ICMPv6';
  }

  final endpoints = source.isEmpty
      ? network
      : '$source${sourcePort == null ? '' : ':$sourcePort'} → '
            '$destination${destinationPort == null ? '' : ':$destinationPort'}';
  final shown = application != 'Unknown'
      ? application
      : transport != 'Unknown'
      ? transport
      : network;
  return CapturePacket(
    number: number,
    timestamp: timestamp,
    capturedLength: bytes.length,
    originalLength: originalLength,
    linkType: linkType,
    networkProtocol: network,
    transportProtocol: transport,
    applicationProtocol: application,
    applicationDetail: applicationDetail,
    source: source,
    destination: destination,
    sourcePort: sourcePort,
    destinationPort: destinationPort,
    summary:
        '$shown${applicationDetail.isEmpty ? '' : ' · $applicationDetail'}  $endpoints',
    bytes: bytes,
  );
}

String _applicationDetail(String protocol, Uint8List bytes, int offset) {
  if (offset < 0 || offset >= bytes.length) return '';
  try {
    return switch (protocol) {
      'DNS' => _dnsDetail(bytes, offset),
      'HTTP' => _httpDetail(bytes, offset),
      'HTTPS' => _tlsClientHelloDetail(bytes, offset),
      _ => '',
    };
  } on Object {
    return '';
  }
}

String _dnsDetail(Uint8List bytes, int offset) {
  if (offset + 12 > bytes.length) return '';
  final data = ByteData.sublistView(bytes);
  final flags = data.getUint16(offset + 2, Endian.big);
  final questions = data.getUint16(offset + 4, Endian.big);
  if (questions == 0) return (flags & 0x8000) == 0 ? 'Query' : 'Response';
  final decoded = _dnsName(bytes, offset + 12, offset, <int>{});
  if (decoded.$1.isEmpty) return '';
  final typeOffset = decoded.$2;
  final type = typeOffset + 2 <= bytes.length
      ? data.getUint16(typeOffset, Endian.big)
      : 0;
  final typeName =
      const {
        1: 'A',
        2: 'NS',
        5: 'CNAME',
        6: 'SOA',
        12: 'PTR',
        15: 'MX',
        16: 'TXT',
        28: 'AAAA',
        33: 'SRV',
        65: 'HTTPS',
      }[type] ??
      'TYPE$type';
  return '${(flags & 0x8000) == 0 ? 'Query' : 'Response'} $typeName ${decoded.$1}';
}

(String, int) _dnsName(
  Uint8List bytes,
  int offset,
  int messageStart,
  Set<int> visited,
) {
  if (!visited.add(offset)) return ('', offset);
  final labels = <String>[];
  var cursor = offset;
  var next = offset;
  var jumped = false;
  while (cursor < bytes.length) {
    final length = bytes[cursor++];
    if (length == 0) {
      if (!jumped) next = cursor;
      break;
    }
    if ((length & 0xC0) == 0xC0) {
      if (cursor >= bytes.length) return ('', next);
      final pointer = ((length & 0x3F) << 8) | bytes[cursor++];
      if (!jumped) next = cursor;
      jumped = true;
      final nested = _dnsName(
        bytes,
        messageStart + pointer,
        messageStart,
        visited,
      );
      if (nested.$1.isNotEmpty) labels.add(nested.$1);
      break;
    }
    if (length > 63 || cursor + length > bytes.length) return ('', next);
    labels.add(
      ascii.decode(bytes.sublist(cursor, cursor + length), allowInvalid: true),
    );
    cursor += length;
    if (!jumped) next = cursor;
  }
  return (labels.join('.'), next);
}

String _httpDetail(Uint8List bytes, int offset) {
  final end = (offset + 4096).clamp(offset, bytes.length).toInt();
  final text = latin1.decode(bytes.sublist(offset, end), allowInvalid: true);
  final lines = text.split(RegExp(r'\r?\n'));
  if (lines.isEmpty) return '';
  final first = lines.first.trim();
  final request = RegExp(
    r'^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|CONNECT|TRACE)\s+(\S+)\s+HTTP/\d(?:\.\d)?$',
  ).firstMatch(first);
  if (request != null) {
    String? host;
    for (final line in lines.skip(1)) {
      final match = RegExp(
        r'^Host:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (match != null) {
        host = match.group(1)!.trim();
        break;
      }
    }
    return '${request.group(1)} ${host ?? ''}${request.group(2)}';
  }
  final response = RegExp(
    r'^HTTP/\d(?:\.\d)?\s+(\d{3})(?:\s+(.+))?',
  ).firstMatch(first);
  return response == null
      ? ''
      : 'Response ${response.group(1)}${response.group(2) == null ? '' : ' ${response.group(2)}'}';
}

String _tlsClientHelloDetail(Uint8List bytes, int offset) {
  if (offset + 9 > bytes.length ||
      bytes[offset] != 22 ||
      bytes[offset + 5] != 1) {
    return '';
  }
  var cursor = offset + 9 + 2 + 32;
  if (cursor >= bytes.length) return '';
  final sessionLength = bytes[cursor++];
  cursor += sessionLength;
  if (cursor + 2 > bytes.length) return '';
  final cipherLength = (bytes[cursor] << 8) | bytes[cursor + 1];
  cursor += 2 + cipherLength;
  if (cursor >= bytes.length) return '';
  final compressionLength = bytes[cursor++];
  cursor += compressionLength;
  if (cursor + 2 > bytes.length) return '';
  final extensionsLength = (bytes[cursor] << 8) | bytes[cursor + 1];
  cursor += 2;
  final extensionsEnd = (cursor + extensionsLength)
      .clamp(cursor, bytes.length)
      .toInt();
  while (cursor + 4 <= extensionsEnd) {
    final type = (bytes[cursor] << 8) | bytes[cursor + 1];
    final length = (bytes[cursor + 2] << 8) | bytes[cursor + 3];
    cursor += 4;
    if (cursor + length > extensionsEnd) break;
    if (type == 0 && length >= 5) {
      var nameCursor = cursor + 2;
      final listEnd = cursor + length;
      while (nameCursor + 3 <= listEnd) {
        final nameType = bytes[nameCursor++];
        final nameLength = (bytes[nameCursor] << 8) | bytes[nameCursor + 1];
        nameCursor += 2;
        if (nameCursor + nameLength > listEnd) break;
        if (nameType == 0) {
          final host = ascii.decode(
            bytes.sublist(nameCursor, nameCursor + nameLength),
            allowInvalid: true,
          );
          return host.isEmpty ? '' : 'SNI $host';
        }
        nameCursor += nameLength;
      }
    }
    cursor += length;
  }
  return 'TLS ClientHello';
}

String _applicationProtocol(int source, int destination, String transport) {
  final ports = {source, destination};
  if (ports.contains(53)) return 'DNS';
  if (ports.contains(67) || ports.contains(68)) return 'DHCP';
  if (ports.contains(80) || ports.contains(8080)) return 'HTTP';
  if (ports.contains(443)) return transport == 'UDP' ? 'QUIC' : 'HTTPS';
  if (ports.contains(22)) return 'SSH';
  if (ports.contains(23)) return 'Telnet';
  if (ports.contains(123)) return 'NTP';
  if (ports.contains(161) || ports.contains(162)) return 'SNMP';
  if (ports.contains(514) || ports.contains(601) || ports.contains(6514))
    return 'Syslog';
  if (ports.contains(1883) || ports.contains(8883)) return 'MQTT';
  if (ports.contains(445)) return 'SMB';
  return 'Unknown';
}

String _ipv4(Uint8List bytes, int offset) =>
    '${bytes[offset]}.${bytes[offset + 1]}.${bytes[offset + 2]}.${bytes[offset + 3]}';

String _ipv6(Uint8List bytes, int offset) {
  final groups = <String>[];
  for (var i = 0; i < 16; i += 2) {
    groups.add(
      ((bytes[offset + i] << 8) | bytes[offset + i + 1]).toRadixString(16),
    );
  }
  return groups.join(':');
}

Future<Uint8List> _readExact(
  RandomAccessFile file,
  int count,
  String label,
) async {
  if (count == 0) return Uint8List(0);
  final bytes = await file.read(count);
  if (bytes.length != count)
    throw FormatException('$label 被截断，需要 $count 字节，实际 ${bytes.length} 字节');
  return Uint8List.fromList(bytes);
}

String captureBytesLabel(int value) {
  if (value >= 1024 * 1024 * 1024)
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  if (value >= 1024 * 1024)
    return '${(value / (1024 * 1024)).toStringAsFixed(2)} MB';
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '$value B';
}
