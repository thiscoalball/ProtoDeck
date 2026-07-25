import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum HttpSecurityObservation {
  plainHttp,
  hstsMissing,
  contentSecurityPolicyMissing,
  noSniffMissing,
  referrerPolicyMissing,
  permissionsPolicyMissing,
}

class HttpDiagnosticResult {
  const HttpDiagnosticResult({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.body,
    required this.totalTime,
    required this.dnsTime,
    required this.connectTime,
    required this.timeToFirstByte,
    required this.preTransferTime,
    required this.downloadTime,
    required this.redirects,
    required this.remoteAddress,
    required this.receivedBytes,
    required this.bodyTruncated,
    required this.localAddress,
    required this.localPort,
    required this.remotePort,
    required this.persistentConnection,
    required this.compressionState,
    required this.contentType,
    required this.charset,
    required this.securityObservations,
    this.certificate,
  });

  final int statusCode;
  final String reasonPhrase;
  final Map<String, String> headers;
  final String body;
  final Duration totalTime;
  final Duration dnsTime;
  final Duration connectTime;
  final Duration timeToFirstByte;
  final Duration preTransferTime;
  final Duration downloadTime;
  final List<String> redirects;
  final String? remoteAddress;
  final int receivedBytes;
  final bool bodyTruncated;
  final String? localAddress;
  final int? localPort;
  final int? remotePort;
  final bool persistentConnection;
  final String compressionState;
  final String? contentType;
  final String? charset;
  final List<HttpSecurityObservation> securityObservations;
  final TlsCertificateInfo? certificate;

  double get averageBytesPerSecond => totalTime.inMicroseconds == 0
      ? 0
      : receivedBytes * 1000000 / totalTime.inMicroseconds;
}

class TlsCertificateInfo {
  const TlsCertificateInfo({
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
  });

  final String subject;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;
}

class HttpDiagnosticService {
  Future<HttpDiagnosticResult> request({
    required Uri uri,
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
    Duration timeout = const Duration(seconds: 15),
    bool followRedirects = true,
    int maxRedirects = 5,
    int maxBodyBytes = 1024 * 1024,
  }) async {
    if (!['http', 'https'].contains(uri.scheme))
      throw const FormatException('URL 必须以 http:// 或 https:// 开头');
    if (uri.host.isEmpty) throw const FormatException('URL 缺少主机名');
    if (maxBodyBytes < 0 || maxBodyBytes > 16 * 1024 * 1024) {
      throw const FormatException('响应正文保留上限应为 0～16 MiB');
    }
    final watch = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = timeout;
    var dnsTime = Duration.zero;
    var connectTime = Duration.zero;
    String? observedLocalAddress;
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (target, proxyHost, proxyPort) async {
      final host = proxyHost ?? target.host;
      final port = proxyPort ?? target.port;
      final dnsWatch = Stopwatch()..start();
      final literal = InternetAddress.tryParse(host);
      final addresses = literal == null
          ? await InternetAddress.lookup(host).timeout(timeout)
          : [literal];
      dnsWatch.stop();
      dnsTime += dnsWatch.elapsed;
      if (addresses.isEmpty) throw SocketException('无法解析 $host');
      final connectWatch = Stopwatch()..start();
      final original = await Socket.startConnect(addresses.first, port);
      final measuredSocket = original.socket.then((socket) {
        connectWatch.stop();
        connectTime += connectWatch.elapsed;
        observedLocalAddress = socket.address.address;
        return socket;
      });
      return ConnectionTask.fromSocket(measuredSocket, original.cancel);
    };
    try {
      final request = await client
          .openUrl(method.toUpperCase(), uri)
          .timeout(timeout);
      request.followRedirects = followRedirects;
      request.maxRedirects = maxRedirects.clamp(0, 20);
      headers.forEach(request.headers.set);
      if (body != null && body.isNotEmpty) request.add(utf8.encode(body));
      final response = await request.close().timeout(timeout);
      final timeToFirstByte = watch.elapsed;
      final preTransferTime = timeToFirstByte - dnsTime - connectTime;
      final downloadWatch = Stopwatch()..start();
      final bytes = <int>[];
      var receivedBytes = 0;
      await for (final chunk in response.timeout(timeout)) {
        receivedBytes += chunk.length;
        if (bytes.length < maxBodyBytes) {
          bytes.addAll(chunk.take(maxBodyBytes - bytes.length));
        }
      }
      downloadWatch.stop();
      watch.stop();
      final responseHeaders = <String, String>{};
      response.headers.forEach(
        (name, values) => responseHeaders[name] = values.join(', '),
      );
      final certificate = response.certificate;
      final connection = response.connectionInfo;
      final contentType = response.headers.contentType;
      return HttpDiagnosticResult(
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        headers: responseHeaders,
        body: utf8.decode(bytes, allowMalformed: true),
        totalTime: watch.elapsed,
        dnsTime: dnsTime,
        connectTime: connectTime,
        timeToFirstByte: timeToFirstByte,
        preTransferTime: preTransferTime.isNegative
            ? Duration.zero
            : preTransferTime,
        downloadTime: downloadWatch.elapsed,
        redirects: response.redirects
            .map((item) => item.location.toString())
            .toList(),
        remoteAddress: response.connectionInfo?.remoteAddress.address,
        receivedBytes: receivedBytes,
        bodyTruncated: receivedBytes > bytes.length,
        localAddress: observedLocalAddress,
        localPort: connection?.localPort,
        remotePort: connection?.remotePort,
        persistentConnection: response.persistentConnection,
        compressionState: response.compressionState.name,
        contentType: contentType?.mimeType,
        charset: contentType?.charset,
        securityObservations: _securityObservations(
          uri: uri,
          headers: responseHeaders,
        ),
        certificate: certificate == null
            ? null
            : TlsCertificateInfo(
                subject: certificate.subject,
                issuer: certificate.issuer,
                validFrom: certificate.startValidity,
                validTo: certificate.endValidity,
              ),
      );
    } finally {
      client.close(force: true);
    }
  }

  List<HttpSecurityObservation> _securityObservations({
    required Uri uri,
    required Map<String, String> headers,
  }) {
    final observations = <HttpSecurityObservation>[];
    if (uri.scheme == 'http') {
      observations.add(HttpSecurityObservation.plainHttp);
    } else if (!headers.containsKey('strict-transport-security')) {
      observations.add(HttpSecurityObservation.hstsMissing);
    }
    if (!headers.containsKey('content-security-policy')) {
      observations.add(HttpSecurityObservation.contentSecurityPolicyMissing);
    }
    if (headers['x-content-type-options']?.toLowerCase() != 'nosniff') {
      observations.add(HttpSecurityObservation.noSniffMissing);
    }
    if (!headers.containsKey('referrer-policy')) {
      observations.add(HttpSecurityObservation.referrerPolicyMissing);
    }
    if (!headers.containsKey('permissions-policy')) {
      observations.add(HttpSecurityObservation.permissionsPolicyMissing);
    }
    return List.unmodifiable(observations);
  }
}
