import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'dns_service.dart';

class TlsInspectionResult {
  const TlsInspectionResult({
    required this.host,
    required this.address,
    required this.resolvedAddresses,
    required this.port,
    required this.dnsTime,
    required this.connectTime,
    required this.handshakeTime,
    required this.totalTime,
    required this.trusted,
    required this.selectedProtocol,
    required this.requestedProtocols,
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    required this.sha1Fingerprint,
    required this.sha256Fingerprint,
    required this.derLength,
    required this.certificatePem,
  });

  final String host;
  final String address;
  final List<String> resolvedAddresses;
  final int port;
  final Duration dnsTime;
  final Duration connectTime;
  final Duration handshakeTime;
  final Duration totalTime;
  final bool trusted;
  final String? selectedProtocol;
  final List<String> requestedProtocols;
  final String subject;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;
  final String sha1Fingerprint;
  final String sha256Fingerprint;
  final int derLength;
  final String certificatePem;

  bool get expired => DateTime.now().isAfter(validTo);
  bool get notYetValid => DateTime.now().isBefore(validFrom);
  bool get selfIssued => subject == issuer;
  InternetAddressType get addressType =>
      InternetAddress.tryParse(address)?.type ?? InternetAddressType.any;
  int get daysRemaining => validTo.difference(DateTime.now()).inDays;
}

class TlsInspectionService {
  Future<TlsInspectionResult> inspect(
    String host, {
    int port = 443,
    Duration timeout = const Duration(seconds: 10),
    bool allowInvalidCertificate = false,
    List<String> supportedProtocols = const ['h2', 'http/1.1'],
  }) async {
    final normalized = host.trim();
    if (normalized.isEmpty) throw const FormatException('主机名不能为空');
    if (port < 1 || port > 65535) {
      throw const FormatException('端口范围应为 1～65535');
    }
    final totalWatch = Stopwatch()..start();
    final dnsWatch = Stopwatch()..start();
    final literal = InternetAddress.tryParse(normalized);
    final addresses = literal == null
        ? await InternetAddress.lookup(normalized).timeout(timeout)
        : [literal];
    dnsWatch.stop();
    if (addresses.isEmpty) throw StateError('域名未解析到 IP 地址');

    Socket? transport;
    InternetAddress? connectedAddress;
    Object? lastConnectError;
    final connectWatch = Stopwatch()..start();
    for (final address in addresses) {
      final remaining = timeout - totalWatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('TCP 连接超时', timeout);
      }
      try {
        transport = await Socket.connect(address, port, timeout: remaining);
        connectedAddress = address;
        break;
      } on Object catch (error) {
        lastConnectError = error;
      }
    }
    connectWatch.stop();
    if (transport == null || connectedAddress == null) {
      throw SocketException('TCP 连接失败：$lastConnectError');
    }

    var trusted = true;
    final handshakeWatch = Stopwatch()..start();
    SecureSocket? socket;
    try {
      final remaining = timeout - totalWatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('TLS 握手超时', timeout);
      }
      socket = await SecureSocket.secure(
        transport,
        host: normalized,
        supportedProtocols: supportedProtocols,
        onBadCertificate: (_) {
          trusted = false;
          return allowInvalidCertificate;
        },
      ).timeout(remaining);
      handshakeWatch.stop();
      totalWatch.stop();
      final certificate = socket.peerCertificate;
      if (certificate == null) throw StateError('对端没有提供证书');
      return TlsInspectionResult(
        host: normalized,
        address: socket.remoteAddress.address,
        resolvedAddresses: [for (final address in addresses) address.address],
        port: port,
        dnsTime: dnsWatch.elapsed,
        connectTime: connectWatch.elapsed,
        handshakeTime: handshakeWatch.elapsed,
        totalTime: totalWatch.elapsed,
        trusted: trusted,
        selectedProtocol: socket.selectedProtocol,
        requestedProtocols: List.unmodifiable(supportedProtocols),
        subject: certificate.subject,
        issuer: certificate.issuer,
        validFrom: certificate.startValidity,
        validTo: certificate.endValidity,
        sha1Fingerprint: _fingerprint(sha1.convert(certificate.der).bytes),
        sha256Fingerprint: _fingerprint(sha256.convert(certificate.der).bytes),
        derLength: certificate.der.length,
        certificatePem: certificate.pem,
      );
    } on Object {
      if (handshakeWatch.isRunning) handshakeWatch.stop();
      if (totalWatch.isRunning) totalWatch.stop();
      rethrow;
    } finally {
      if (socket != null) {
        await socket.close();
      } else {
        await transport.close();
      }
    }
  }

  static String _fingerprint(List<int> bytes) => bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}

class IpOwnershipResult {
  const IpOwnershipResult({
    required this.query,
    required this.address,
    required this.rdapEndpoint,
    required this.handle,
    required this.name,
    required this.country,
    required this.type,
    required this.startAddress,
    required this.endAddress,
    required this.cidrs,
    required this.asn,
    required this.asName,
    required this.asCountry,
    required this.registry,
  });

  final String query;
  final String address;
  final String rdapEndpoint;
  final String? handle;
  final String? name;
  final String? country;
  final String? type;
  final String? startAddress;
  final String? endAddress;
  final List<String> cidrs;
  final String? asn;
  final String? asName;
  final String? asCountry;
  final String? registry;
}

class IpOwnershipService {
  Future<IpOwnershipResult> lookup(
    String query, {
    String rdapBase = 'https://rdap.org/ip/',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final target = query.trim();
    if (target.isEmpty) throw const FormatException('IP 或域名不能为空');
    var address = InternetAddress.tryParse(target);
    address ??= (await InternetAddress.lookup(target).timeout(
      timeout,
    )).where((item) => item.type == InternetAddressType.IPv4).firstOrNull;
    address ??= (await InternetAddress.lookup(target).timeout(timeout)).first;
    if (_isNonPublic(address)) {
      throw const FormatException('RDAP/ASN 只适用于公网地址；当前目标是私网、回环或链路本地地址');
    }
    final endpoint = Uri.parse('$rdapBase${address.address}');
    final response = await http
        .get(endpoint, headers: const {'Accept': 'application/rdap+json'})
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('RDAP 返回 HTTP ${response.statusCode}', uri: endpoint);
    }
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
    final cidrs = <String>[];
    for (final item in json['cidr0_cidrs'] as List<Object?>? ?? const []) {
      if (item is! Map<String, Object?>) continue;
      final prefix = item['v4prefix'] ?? item['v6prefix'];
      final length = item['length'];
      if (prefix != null && length != null) cidrs.add('$prefix/$length');
    }
    final asnInfo = await _lookupAsn(address, timeout);
    return IpOwnershipResult(
      query: target,
      address: address.address,
      rdapEndpoint: endpoint.toString(),
      handle: json['handle'] as String?,
      name: json['name'] as String?,
      country: json['country'] as String?,
      type: json['type'] as String?,
      startAddress: json['startAddress'] as String?,
      endAddress: json['endAddress'] as String?,
      cidrs: cidrs,
      asn: asnInfo.$1,
      asName: asnInfo.$2,
      asCountry: asnInfo.$3,
      registry: asnInfo.$4,
    );
  }

  Future<(String?, String?, String?, String?)> _lookupAsn(
    InternetAddress address,
    Duration timeout,
  ) async {
    final originName = address.type == InternetAddressType.IPv4
        ? '${address.address.split('.').reversed.join('.')}.origin.asn.cymru.com'
        : '${address.rawAddress.map((b) => b.toRadixString(16).padLeft(2, '0')).join().split('').reversed.join('.')}.origin6.asn.cymru.com';
    final origin = await DnsService().lookup(
      originName,
      type: DnsRecordType.txt,
      transport: DnsTransport.udp,
      server: '223.5.5.5',
      timeout: timeout,
    );
    if (!origin.success || origin.records.isEmpty)
      return (null, null, null, null);
    final fields = origin.records.first.data
        .replaceAll('"', '')
        .split('|')
        .map((e) => e.trim())
        .toList();
    if (fields.isEmpty || fields.first.isEmpty) return (null, null, null, null);
    final asn = fields.first.split(' ').first;
    final detail = await DnsService().lookup(
      'AS$asn.asn.cymru.com',
      type: DnsRecordType.txt,
      transport: DnsTransport.udp,
      server: '223.5.5.5',
      timeout: timeout,
    );
    final detailFields = detail.records.isEmpty
        ? <String>[]
        : detail.records.first.data
              .replaceAll('"', '')
              .split('|')
              .map((e) => e.trim())
              .toList();
    return (
      asn,
      detailFields.length > 4 ? detailFields[4] : null,
      detailFields.length > 1 ? detailFields[1] : null,
      detailFields.length > 2 ? detailFields[2] : null,
    );
  }

  bool _isNonPublic(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast)
      return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) ||
          bytes[0] == 0 ||
          bytes[0] >= 224;
    }
    return (bytes[0] & 0xfe) == 0xfc;
  }
}

extension _FirstOrNullOwnership<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
