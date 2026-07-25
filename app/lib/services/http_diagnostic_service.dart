import 'dart:async';
import 'dart:convert';
import 'dart:io';

class HttpDiagnosticResult {
  const HttpDiagnosticResult({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.body,
    required this.totalTime,
    required this.dnsTime,
    required this.timeToFirstByte,
    required this.downloadTime,
    required this.redirects,
    required this.remoteAddress,
    this.certificate,
  });

  final int statusCode;
  final String reasonPhrase;
  final Map<String, String> headers;
  final String body;
  final Duration totalTime;
  final Duration dnsTime;
  final Duration timeToFirstByte;
  final Duration downloadTime;
  final List<String> redirects;
  final String? remoteAddress;
  final TlsCertificateInfo? certificate;
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
  }) async {
    if (!['http', 'https'].contains(uri.scheme))
      throw const FormatException('URL 必须以 http:// 或 https:// 开头');
    final watch = Stopwatch()..start();
    final dnsWatch = Stopwatch()..start();
    if (InternetAddress.tryParse(uri.host) == null) {
      await InternetAddress.lookup(uri.host).timeout(timeout);
    }
    dnsWatch.stop();
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .openUrl(method.toUpperCase(), uri)
          .timeout(timeout);
      headers.forEach(request.headers.set);
      if (body != null && body.isNotEmpty) request.add(utf8.encode(body));
      final response = await request.close().timeout(timeout);
      final timeToFirstByte = watch.elapsed;
      final downloadWatch = Stopwatch()..start();
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        if (bytes.length < 1024 * 1024)
          bytes.addAll(chunk.take(1024 * 1024 - bytes.length));
      }
      downloadWatch.stop();
      watch.stop();
      final responseHeaders = <String, String>{};
      response.headers.forEach(
        (name, values) => responseHeaders[name] = values.join(', '),
      );
      final certificate = response.certificate;
      return HttpDiagnosticResult(
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        headers: responseHeaders,
        body: utf8.decode(bytes, allowMalformed: true),
        totalTime: watch.elapsed,
        dnsTime: dnsWatch.elapsed,
        timeToFirstByte: timeToFirstByte,
        downloadTime: downloadWatch.elapsed,
        redirects: response.redirects
            .map((item) => item.location.toString())
            .toList(),
        remoteAddress: response.connectionInfo?.remoteAddress.address,
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
}
