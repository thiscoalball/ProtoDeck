import 'dart:convert';

import 'package:crypto/crypto.dart';

class JwtInspection {
  const JwtInspection({
    required this.header,
    required this.payload,
    required this.algorithm,
    required this.signatureStatus,
    required this.claims,
    required this.warnings,
  });

  final Map<String, Object?> header;
  final Map<String, Object?> payload;
  final String algorithm;
  final String signatureStatus;
  final Map<String, String> claims;
  final List<String> warnings;
}

class JwtWorkbenchService {
  JwtInspection inspect(String source, {String secret = ''}) {
    final parts = source.trim().split('.');
    if (parts.length != 3) throw const FormatException('JWT 必须由三段组成');
    final header = _decodeObject(parts[0], 'Header');
    final payload = _decodeObject(parts[1], 'Payload');
    final algorithm = header['alg']?.toString() ?? '';
    final status = _verify(
      '${parts[0]}.${parts[1]}',
      parts[2],
      algorithm,
      secret,
    );
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final claims = <String, String>{};
    final warnings = <String>[];
    for (final key in ['iat', 'nbf', 'exp']) {
      final value = payload[key];
      if (value is num) {
        claims[key] = DateTime.fromMillisecondsSinceEpoch(
          value.toInt() * 1000,
          isUtc: true,
        ).toIso8601String();
      }
    }
    for (final key in ['iss', 'sub', 'aud', 'jti', 'scope']) {
      if (payload[key] != null) claims[key] = _display(payload[key]);
    }
    if (algorithm.isEmpty) warnings.add('Header 缺少 alg。');
    if (algorithm.toLowerCase() == 'none')
      warnings.add('alg=none 的 Token 没有完整性保护。');
    final exp = payload['exp'];
    if (exp is num && exp.toInt() <= now) warnings.add('Token 已过期。');
    final nbf = payload['nbf'];
    if (nbf is num && nbf.toInt() > now) warnings.add('Token 尚未进入生效时间。');
    final iat = payload['iat'];
    if (iat is num && iat.toInt() > now + 300)
      warnings.add('iat 比当前时间超前超过 5 分钟。');
    if (payload['exp'] == null) warnings.add('Payload 没有 exp，Token 可能长期有效。');
    if (payload['aud'] == null) warnings.add('Payload 没有 aud，调用方应额外限制受众。');
    return JwtInspection(
      header: header,
      payload: payload,
      algorithm: algorithm,
      signatureStatus: status,
      claims: claims,
      warnings: warnings,
    );
  }

  String sign({
    required String headerSource,
    required String payloadSource,
    required String algorithm,
    required String secret,
  }) {
    if (secret.isEmpty) throw const FormatException('签发 HMAC JWT 需要密钥');
    final header = _jsonObject(headerSource, 'Header')..['alg'] = algorithm;
    header.putIfAbsent('typ', () => 'JWT');
    final payload = _jsonObject(payloadSource, 'Payload');
    final encodedHeader = _encode(jsonEncode(header));
    final encodedPayload = _encode(jsonEncode(payload));
    final input = '$encodedHeader.$encodedPayload';
    final digest = Hmac(
      _hash(algorithm),
      utf8.encode(secret),
    ).convert(utf8.encode(input));
    return '$input.${base64Url.encode(digest.bytes).replaceAll('=', '')}';
  }

  Map<String, Object?> _decodeObject(String source, String name) {
    try {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64.normalize(source))),
      );
      if (decoded is! Map) throw FormatException('$name 必须是 JSON Object');
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('$name Base64URL 或 JSON 无效：$error');
    }
  }

  Map<String, Object?> _jsonObject(String source, String name) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw FormatException('$name 必须是 JSON Object');
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
  }

  String _verify(
    String input,
    String signature,
    String algorithm,
    String secret,
  ) {
    if (algorithm == 'none') return signature.isEmpty ? 'UNSIGNED' : 'INVALID';
    if (!{'HS256', 'HS384', 'HS512'}.contains(algorithm))
      return 'NOT SUPPORTED';
    if (secret.isEmpty) return 'NOT VERIFIED';
    late final List<int> actual;
    try {
      actual = base64Url.decode(base64.normalize(signature));
    } on Object {
      return 'INVALID';
    }
    final expected = Hmac(
      _hash(algorithm),
      utf8.encode(secret),
    ).convert(utf8.encode(input)).bytes;
    if (actual.length != expected.length) return 'INVALID';
    var difference = 0;
    for (var index = 0; index < actual.length; index++) {
      difference |= actual[index] ^ expected[index];
    }
    return difference == 0 ? 'VALID' : 'INVALID';
  }

  Hash _hash(String algorithm) => switch (algorithm) {
    'HS256' => sha256,
    'HS384' => sha384,
    'HS512' => sha512,
    _ => throw const FormatException('只支持 HS256、HS384 与 HS512 签发'),
  };

  String _encode(String source) =>
      base64Url.encode(utf8.encode(source)).replaceAll('=', '');

  String _display(Object? value) => value is String ? value : jsonEncode(value);
}
