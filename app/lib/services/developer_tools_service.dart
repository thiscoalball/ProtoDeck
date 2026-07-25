import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

class RegexMatchResult {
  const RegexMatchResult({
    required this.start,
    required this.end,
    required this.text,
    required this.groups,
  });

  final int start;
  final int end;
  final String text;
  final List<String?> groups;
}

enum DiffKind { equal, added, removed }

class DiffPart {
  const DiffPart(this.kind, this.text);
  final DiffKind kind;
  final String text;
}

class DeveloperToolsService {
  Map<String, String> digestAll(String input, {String key = ''}) {
    final result = <String, String>{
      'MD5': digestText(input, 'md5', key: key),
      'SHA-1': digestText(input, 'sha1', key: key),
      'SHA-256': digestText(input, 'sha256', key: key),
      'SHA-512': digestText(input, 'sha512', key: key),
    };
    if (key.isEmpty) result['CRC32'] = digestText(input, 'crc32');
    return result;
  }

  String digestText(String input, String algorithm, {String key = ''}) {
    final bytes = utf8.encode(input);
    if (algorithm.toLowerCase() == 'crc32') {
      if (key.isNotEmpty) throw const FormatException('CRC32 不支持 HMAC 密钥');
      var crc = 0xffffffff;
      for (final byte in bytes) {
        crc ^= byte;
        for (var bit = 0; bit < 8; bit++) {
          crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
        }
      }
      return ((crc ^ 0xffffffff) & 0xffffffff)
          .toRadixString(16)
          .padLeft(8, '0');
    }
    final Hash hash = switch (algorithm.toLowerCase()) {
      'md5' => md5,
      'sha1' => sha1,
      'sha256' => sha256,
      'sha512' => sha512,
      _ => throw const FormatException('支持 MD5、SHA-1、SHA-256、SHA-512'),
    };
    return (key.isEmpty
            ? hash.convert(bytes)
            : Hmac(hash, utf8.encode(key)).convert(bytes))
        .toString();
  }

  /// Calculates common file digests with bounded memory usage.
  Future<Map<String, String>> digestFile(File file) async {
    if (!await file.exists()) throw StateError('文件不存在');
    Future<String> calculate(Hash algorithm) async =>
        (await algorithm.bind(file.openRead()).first).toString();
    return {
      'MD5': await calculate(md5),
      'SHA-1': await calculate(sha1),
      'SHA-256': await calculate(sha256),
      'SHA-512': await calculate(sha512),
    };
  }

  String decodeJwt(String input) {
    final parts = input.trim().split('.');
    if (parts.length != 3) throw const FormatException('JWT 必须由三段组成');
    Object decodePart(String value) =>
        jsonDecode(utf8.decode(base64Url.decode(base64.normalize(value))));
    final header = decodePart(parts[0]);
    final payload = decodePart(parts[1]);
    final output = <String>[
      'Header',
      const JsonEncoder.withIndent('  ').convert(header),
      '',
      'Payload',
      const JsonEncoder.withIndent('  ').convert(payload),
      '',
      'Signature (Base64URL)',
      parts[2],
      '',
      '提示：这里只做离线解码，不代表签名有效。',
    ];
    if (payload is Map) {
      for (final key in ['iat', 'nbf', 'exp']) {
        final value = payload[key];
        if (value is num) {
          output.add(
            '$key: ${DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000).toLocal().toIso8601String()}',
          );
        }
      }
    }
    return output.join('\n');
  }

  String generate(String type, {int length = 24}) {
    final random = Random.secure();
    if (type == 'uuid') {
      final bytes = List<int>.generate(16, (_) => random.nextInt(256));
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    }
    if (type == 'ulid') {
      const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
      var time = DateTime.now().millisecondsSinceEpoch;
      final prefix = List<String>.filled(10, '0');
      for (var index = 9; index >= 0; index--) {
        prefix[index] = alphabet[time & 31];
        time ~/= 32;
      }
      return prefix.join() +
          List.generate(16, (_) => alphabet[random.nextInt(32)]).join();
    }
    if (type == 'password') {
      if (length < 4 || length > 256)
        throw const FormatException('密码长度需为 4～256');
      const alphabet =
          r'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*_-+=';
      return List.generate(
        length,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
    }
    throw const FormatException('不支持的生成类型');
  }

  String chmodConvert(String input) {
    final text = input.trim();
    if (RegExp(r'^[0-7]{3,4}$').hasMatch(text)) {
      final digits = text.length == 4 ? text.substring(1) : text;
      final symbolic = StringBuffer();
      for (final value in digits.codeUnits.map((v) => v - 48)) {
        symbolic.write(value & 4 != 0 ? 'r' : '-');
        symbolic.write(value & 2 != 0 ? 'w' : '-');
        symbolic.write(value & 1 != 0 ? 'x' : '-');
      }
      return '八进制: $text\n符号: ${symbolic.toString()}\nchmod $text <file>';
    }
    final normalized = text.replaceAll(RegExp(r'^[d-]'), '');
    if (!RegExp(r'^[rwx-]{9}$').hasMatch(normalized)) {
      throw const FormatException('请输入 755、0755 或 rwxr-xr-x');
    }
    final values = <int>[];
    for (var index = 0; index < 9; index += 3) {
      final part = normalized.substring(index, index + 3);
      values.add(
        (part[0] == 'r' ? 4 : 0) +
            (part[1] == 'w' ? 2 : 0) +
            (part[2] == 'x' ? 1 : 0),
      );
    }
    return '符号: $normalized\n八进制: ${values.join()}\nchmod ${values.join()} <file>';
  }

  String unicodeConvert(String input, {bool decode = false}) {
    if (!decode) {
      return input.runes
          .map(
            (rune) => rune <= 0x7f
                ? String.fromCharCode(rune)
                : '\\u${rune.toRadixString(16).padLeft(rune > 0xffff ? 8 : 4, '0')}',
          )
          .join();
    }
    return input.replaceAllMapped(RegExp(r'\\u\{?([0-9a-fA-F]{4,8})\}?'), (
      match,
    ) {
      final value = int.parse(match.group(1)!, radix: 16);
      return String.fromCharCode(value);
    });
  }

  String htmlEntityConvert(String input, {bool decode = false}) {
    if (!decode) {
      return input
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&#39;');
    }
    return input
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'), (match) {
          final raw = match.group(1)!;
          return String.fromCharCode(
            int.parse(
              raw.startsWith('x') ? raw.substring(1) : raw,
              radix: raw.startsWith('x') ? 16 : 10,
            ),
          );
        })
        .replaceAll('&amp;', '&');
  }

  String hexDump(String input, {bool decode = false}) {
    if (decode) {
      final normalized = input.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      if (normalized.length.isOdd) throw const FormatException('Hex 字节不完整');
      return utf8.decode([
        for (var i = 0; i < normalized.length; i += 2)
          int.parse(normalized.substring(i, i + 2), radix: 16),
      ], allowMalformed: true);
    }
    final bytes = utf8.encode(input);
    final lines = <String>[];
    for (var offset = 0; offset < bytes.length; offset += 16) {
      final row = bytes.sublist(offset, min(offset + 16, bytes.length));
      final hex = row
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .padRight(47);
      final ascii = row
          .map((v) => v >= 32 && v <= 126 ? String.fromCharCode(v) : '.')
          .join();
      lines.add('${offset.toRadixString(16).padLeft(8, '0')}  $hex  |$ascii|');
    }
    return lines.join('\n');
  }

  String inspectUrl(String input) {
    final uri = Uri.parse(input.trim());
    return [
      'scheme: ${uri.scheme}',
      'userInfo: ${uri.userInfo}',
      'host: ${uri.host}',
      'port: ${uri.hasPort ? uri.port : '(默认)'}',
      'path: ${uri.path}',
      'segments: ${uri.pathSegments}',
      'query: ${uri.query}',
      ...uri.queryParametersAll.entries.map((e) => '  ${e.key}: ${e.value}'),
      'fragment: ${uri.fragment}',
      'origin: ${uri.hasScheme && uri.hasAuthority ? uri.origin : '(无)'}',
    ].join('\n');
  }

  String compression(String input, {bool decode = false}) {
    if (decode) {
      final bytes = base64.decode(base64.normalize(input.trim()));
      return utf8.decode(gzip.decode(bytes), allowMalformed: true);
    }
    final source = utf8.encode(input);
    final compressed = gzip.encode(source);
    return '原始: ${source.length} B\nGzip: ${compressed.length} B\n比率: ${(compressed.length / max(1, source.length) * 100).toStringAsFixed(1)}%\n\n${base64.encode(compressed)}';
  }

  String convertStructuredData(String input, String mode) {
    switch (mode) {
      case 'json_yaml':
        return _emitYaml(jsonDecode(input));
      case 'yaml_json':
        return const JsonEncoder.withIndent(
          '  ',
        ).convert(_yamlToDart(loadYaml(input)));
      case 'csv_json':
        final rows = csv.decode(input);
        if (rows.isEmpty) return '[]';
        final headers = rows.first.map((v) => '$v').toList();
        final result = [
          for (final row in rows.skip(1))
            {
              for (var index = 0; index < headers.length; index++)
                headers[index]: index < row.length ? row[index] : null,
            },
        ];
        return const JsonEncoder.withIndent('  ').convert(result);
      case 'json_csv':
        final value = jsonDecode(input);
        if (value is! List || value.whereType<Map>().length != value.length) {
          throw const FormatException('JSON → CSV 需要对象数组');
        }
        final objects = value.cast<Map>();
        final headers = <String>{
          for (final object in objects) ...object.keys.map((key) => '$key'),
        }.toList();
        return csv.encode([
          headers,
          for (final object in objects)
            [for (final header in headers) object[header]],
        ]);
      default:
        throw const FormatException('不支持的结构化数据转换');
    }
  }

  String queryJson(String input, String path) {
    Object? current = jsonDecode(input);
    var expression = path.trim();
    if (!expression.startsWith(r'$')) {
      throw const FormatException(r'查询路径必须以 $ 开头');
    }
    expression = expression.substring(1);
    final tokens = RegExp(
      r'\.([A-Za-z0-9_-]+)|\[([0-9]+|\*)\]',
    ).allMatches(expression);
    if (tokens.map((m) => m.group(0)!).join() != expression) {
      throw const FormatException(r'当前支持 $.name、[0] 和 [*] 查询');
    }
    for (final token in tokens) {
      final key = token.group(1);
      final index = token.group(2);
      if (key != null) {
        if (current is Map && current.containsKey(key)) {
          current = current[key];
        } else if (current is List) {
          current = [
            for (final item in current)
              if (item is Map && item.containsKey(key)) item[key],
          ];
        } else {
          throw FormatException('路径中不存在 .$key');
        }
      } else if (index == '*') {
        if (current is! List) throw const FormatException('[*] 只能用于数组');
      } else {
        final position = int.parse(index!);
        if (current is! List || position >= current.length) {
          throw FormatException('数组下标越界：$position');
        }
        current = current[position];
      }
    }
    return current is String
        ? current
        : const JsonEncoder.withIndent('  ').convert(current);
  }

  String nextCronRuns(String expression, {int count = 10}) {
    final fields = expression.trim().split(RegExp(r'\s+'));
    if (fields.length != 5) {
      throw const FormatException('请输入标准 5 段 Cron：分 时 日 月 周');
    }
    var cursor = DateTime.now();
    cursor = DateTime(
      cursor.year,
      cursor.month,
      cursor.day,
      cursor.hour,
      cursor.minute,
    ).add(const Duration(minutes: 1));
    final results = <DateTime>[];
    for (
      var tries = 0;
      tries < 60 * 24 * 366 * 2 && results.length < count;
      tries++
    ) {
      final weekday = cursor.weekday == DateTime.sunday ? 0 : cursor.weekday;
      if (_cronMatch(fields[0], cursor.minute, 0, 59) &&
          _cronMatch(fields[1], cursor.hour, 0, 23) &&
          _cronMatch(fields[2], cursor.day, 1, 31) &&
          _cronMatch(fields[3], cursor.month, 1, 12) &&
          _cronMatch(fields[4], weekday, 0, 7)) {
        results.add(cursor);
      }
      cursor = cursor.add(const Duration(minutes: 1));
    }
    if (results.isEmpty) throw const FormatException('两年内没有匹配时间，请检查表达式');
    return [
      '表达式: ${fields.join(' ')}',
      '含义: ${_cronDescribe(fields)}',
      '',
      for (var index = 0; index < results.length; index++)
        '${index + 1}. ${results[index].toLocal().toIso8601String()}',
    ].join('\n');
  }

  bool _cronMatch(String field, int value, int minValue, int maxValue) {
    for (final item in field.split(',')) {
      final stepParts = item.split('/');
      final base = stepParts.first;
      final step = stepParts.length == 2 ? int.tryParse(stepParts[1]) : 1;
      if (step == null || step <= 0) throw FormatException('Cron 步长错误：$item');
      var start = minValue;
      var end = maxValue;
      if (base != '*') {
        final range = base.split('-');
        start = int.tryParse(range.first) ?? -1;
        end = range.length == 2 ? int.tryParse(range[1]) ?? -1 : start;
      }
      if (start < minValue || end > maxValue || start > end) {
        throw FormatException('Cron 范围错误：$item');
      }
      final normalized =
          value == 0 && minValue == 0 && maxValue == 7 && start == 7
          ? 7
          : value;
      if (normalized >= start &&
          normalized <= end &&
          (normalized - start) % step == 0) {
        return true;
      }
    }
    return false;
  }

  String _cronDescribe(List<String> fields) {
    if (fields.join(' ') == '* * * * *') return '每分钟';
    if (fields[0].startsWith('*/') && fields.skip(1).every((v) => v == '*')) {
      return '每 ${fields[0].substring(2)} 分钟';
    }
    return '在满足 分=${fields[0]}、时=${fields[1]}、日=${fields[2]}、月=${fields[3]}、周=${fields[4]} 时执行';
  }

  String endianView(String input, {int width = 32}) {
    if (![16, 32, 64].contains(width))
      throw const FormatException('位宽必须为 16/32/64');
    final value = _parseNumber(input);
    final mask = (BigInt.one << width) - BigInt.one;
    final normalized = value & mask;
    final bytes = [
      for (var shift = width - 8; shift >= 0; shift -= 8)
        ((normalized >> shift) & BigInt.from(255)).toInt(),
    ];
    String render(Iterable<int> values) => values
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join(' ')
        .toUpperCase();
    return '十进制: $normalized\n十六进制: 0x${normalized.toRadixString(16).padLeft(width ~/ 4, '0').toUpperCase()}\n大端字节: ${render(bytes)}\n小端字节: ${render(bytes.reversed)}';
  }

  String parseUserAgent(String input) {
    final value = input.trim();
    if (value.isEmpty) throw const FormatException('请输入 User-Agent');
    String first(RegExp expression, [String fallback = '未知']) =>
        expression.firstMatch(value)?.group(1) ?? fallback;
    final os = value.contains('Android')
        ? 'Android ${first(RegExp(r'Android ([^;\)]+)'))}'
        : value.contains('iPhone') || value.contains('iPad')
        ? 'iOS ${first(RegExp(r'OS ([0-9_]+)')).replaceAll('_', '.')}'
        : value.contains('Windows NT')
        ? 'Windows NT ${first(RegExp(r'Windows NT ([0-9.]+)'))}'
        : value.contains('Mac OS X')
        ? 'macOS ${first(RegExp(r'Mac OS X ([0-9_]+)')).replaceAll('_', '.')}'
        : value.contains('Linux')
        ? 'Linux'
        : '未知';
    final browser = value.contains('Edg/')
        ? 'Edge ${first(RegExp(r'Edg/([^ ]+)'))}'
        : value.contains('Chrome/')
        ? 'Chrome ${first(RegExp(r'Chrome/([^ ]+)'))}'
        : value.contains('Firefox/')
        ? 'Firefox ${first(RegExp(r'Firefox/([^ ]+)'))}'
        : value.contains('Safari/') && value.contains('Version/')
        ? 'Safari ${first(RegExp(r'Version/([^ ]+)'))}'
        : '未知';
    final device = value.contains('Mobile') ? '移动设备' : '桌面/其他设备';
    return '浏览器: $browser\n系统: $os\n设备类型: $device\n移动端: ${value.contains('Mobile') ? '是' : '否'}\nBot/Crawler: ${RegExp(r'bot|crawler|spider', caseSensitive: false).hasMatch(value) ? '可能是' : '否'}';
  }

  String base64EncodeText(String input, {bool urlSafe = false}) {
    final encoded = urlSafe
        ? base64Url.encode(utf8.encode(input))
        : base64.encode(utf8.encode(input));
    return urlSafe ? encoded.replaceAll('=', '') : encoded;
  }

  String base64DecodeText(String input, {bool urlSafe = false}) {
    try {
      final normalized = base64.normalize(input.trim());
      return utf8.decode((urlSafe ? base64Url : base64).decode(normalized));
    } on Object catch (error) {
      throw FormatException('Base64 解码失败：$error');
    }
  }

  String urlEncode(String input, {bool fullUrl = false}) =>
      fullUrl ? Uri.encodeFull(input) : Uri.encodeComponent(input);

  String urlDecode(String input, {bool fullUrl = false}) {
    try {
      return fullUrl ? Uri.decodeFull(input) : Uri.decodeComponent(input);
    } on Object catch (error) {
      throw FormatException('URL 解码失败：$error');
    }
  }

  DateTime timestampToDateTime(String input, {bool utc = false}) {
    final parsed = _parseTimestamp(input);
    final date = DateTime.fromMicrosecondsSinceEpoch(
      parsed.microsecondsSinceEpoch,
      isUtc: utc,
    );
    return utc ? date.toUtc() : date.toLocal();
  }

  Map<String, int> dateTimeToTimestamps(String input) {
    final date = DateTime.tryParse(input.trim());
    if (date == null) throw const FormatException('时间格式错误，请使用 ISO 8601');
    return {
      'seconds': date.millisecondsSinceEpoch ~/ 1000,
      'milliseconds': date.millisecondsSinceEpoch,
      'microseconds': date.microsecondsSinceEpoch,
      'nanoseconds': date.microsecondsSinceEpoch * 1000,
    };
  }

  /// Accepts Unix seconds/milliseconds/microseconds/nanoseconds or an ISO 8601
  /// date and returns the representations engineers usually need together.
  Map<String, String> inspectTimestamp(String input) {
    final text = input.trim();
    if (text.isEmpty) throw const FormatException('请输入时间戳或 ISO 8601 时间');
    final numeric = RegExp(r'^[-+]?\d+$').hasMatch(text);
    late final DateTime instant;
    late final String inputType;
    if (numeric) {
      final parsed = _parseTimestamp(text);
      instant = DateTime.fromMicrosecondsSinceEpoch(
        parsed.microsecondsSinceEpoch,
        isUtc: true,
      );
      inputType = parsed.unit;
    } else {
      final parsed = DateTime.tryParse(text);
      if (parsed == null) {
        throw const FormatException('无法识别时间，请输入 Unix 时间戳或 ISO 8601 时间');
      }
      instant = parsed.toUtc();
      inputType = 'ISO 8601 / 日期时间';
    }
    final local = instant.toLocal();
    final micros = instant.microsecondsSinceEpoch;
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absoluteMinutes = offset.inMinutes.abs();
    final offsetText =
        '$sign${(absoluteMinutes ~/ 60).toString().padLeft(2, '0')}:${(absoluteMinutes % 60).toString().padLeft(2, '0')}';
    return {
      '输入类型': inputType,
      '本地时间': local.toIso8601String(),
      'UTC 时间': instant.toIso8601String(),
      '时区': '${local.timeZoneName} (UTC$offsetText)',
      'Unix 秒': '${micros ~/ Duration.microsecondsPerSecond}',
      'Unix 毫秒': '${micros ~/ Duration.microsecondsPerMillisecond}',
      'Unix 微秒': '$micros',
      'Unix 纳秒': '${micros * 1000}',
      'RFC 3339': instant.toIso8601String(),
      '星期': const ['一', '二', '三', '四', '五', '六', '日'][local.weekday - 1],
    };
  }

  List<Map<String, String>> inspectTimestamps(String input) {
    final lines = const LineSplitter()
        .convert(input)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) throw const FormatException('请输入至少一条时间');
    if (lines.length > 200) throw const FormatException('批量转换最多支持 200 行');
    return [
      for (final line in lines) {'原始输入': line, ...inspectTimestamp(line)},
    ];
  }

  List<RegexMatchResult> testRegex(
    String pattern,
    String input, {
    bool caseSensitive = true,
    bool multiLine = false,
    bool dotAll = false,
  }) {
    try {
      final expression = RegExp(
        pattern,
        caseSensitive: caseSensitive,
        multiLine: multiLine,
        dotAll: dotAll,
        unicode: true,
      );
      return expression
          .allMatches(input)
          .map((match) {
            return RegexMatchResult(
              start: match.start,
              end: match.end,
              text: match.group(0) ?? '',
              groups: [
                for (var index = 1; index <= match.groupCount; index++)
                  match.group(index),
              ],
            );
          })
          .toList(growable: false);
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('正则表达式错误：$error');
    }
  }

  String regexReplace(
    String pattern,
    String input,
    String replacement, {
    bool caseSensitive = true,
    bool multiLine = false,
    bool dotAll = false,
    bool replaceAll = true,
  }) {
    final expression = RegExp(
      pattern,
      caseSensitive: caseSensitive,
      multiLine: multiLine,
      dotAll: dotAll,
      unicode: true,
    );
    String expand(Match match) => replacement.replaceAllMapped(
      RegExp(r'\$(\$|\d+)'),
      (token) {
        final reference = token.group(1)!;
        if (reference == r'$') return r'$';
        final index = int.parse(reference);
        return index <= match.groupCount ? match.group(index) ?? '' : token[0]!;
      },
    );
    if (replaceAll) return input.replaceAllMapped(expression, expand);
    final first = expression.firstMatch(input);
    if (first == null) return input;
    return input.replaceRange(first.start, first.end, expand(first));
  }

  Map<String, String> radixRepresentations(String input, int from) {
    if (from < 2 || from > 36) throw const FormatException('源进制必须为 2～36');
    final normalized = input.trim().replaceAll('_', '');
    final negative = normalized.startsWith('-');
    final body = negative ? normalized.substring(1) : normalized;
    final value = BigInt.tryParse(body, radix: from);
    if (value == null) throw FormatException('$input 不是有效的 $from 进制数');
    final signed = negative ? -value : value;
    String render(int radix, String prefix) {
      final magnitude = signed.abs().toRadixString(radix).toUpperCase();
      return '${signed.isNegative ? '-' : ''}$prefix$magnitude';
    }

    return {
      '二进制': render(2, '0b'),
      '八进制': render(8, '0o'),
      '十进制': signed.toString(),
      '十六进制': render(16, '0x'),
      'Base36': render(36, ''),
    };
  }

  ({int microsecondsSinceEpoch, String unit}) _parseTimestamp(String input) {
    final text = input.trim();
    final value = int.tryParse(text);
    if (value == null) throw const FormatException('请输入有效的整数时间戳');
    final digits = text.replaceFirst(RegExp(r'^[-+]'), '').length;
    if (digits <= 10) {
      return (
        microsecondsSinceEpoch: value * Duration.microsecondsPerSecond,
        unit: 'Unix 秒',
      );
    }
    if (digits <= 13) {
      return (
        microsecondsSinceEpoch: value * Duration.microsecondsPerMillisecond,
        unit: 'Unix 毫秒',
      );
    }
    if (digits <= 16) {
      return (microsecondsSinceEpoch: value, unit: 'Unix 微秒');
    }
    return (microsecondsSinceEpoch: value ~/ 1000, unit: 'Unix 纳秒');
  }

  String convertRadix(String input, int from, int to) {
    if (from < 2 || from > 36 || to < 2 || to > 36) {
      throw const FormatException('进制必须为 2～36');
    }
    final text = input.trim();
    final negative = text.startsWith('-');
    final body = negative ? text.substring(1) : text;
    final value = BigInt.tryParse(body, radix: from);
    if (value == null) throw FormatException('$input 不是有效的 $from 进制数');
    return '${negative ? '-' : ''}${value.toRadixString(to).toUpperCase()}';
  }

  Map<String, String> bitCalculate({
    required String left,
    required String operation,
    String? right,
    int width = 32,
  }) {
    if (![8, 16, 32, 64].contains(width))
      throw const FormatException('位宽必须为 8/16/32/64');
    final a = _parseNumber(left);
    final b = right == null || right.trim().isEmpty
        ? BigInt.zero
        : _parseNumber(right);
    final mask = (BigInt.one << width) - BigInt.one;
    final result =
        switch (operation) {
          'AND' => a & b,
          'OR' => a | b,
          'XOR' => a ^ b,
          'NOT' => ~a,
          'SHL' => a << b.toInt(),
          'SHR' => a >> b.toInt(),
          _ => throw const FormatException('不支持的位运算'),
        } &
        mask;
    return {
      'decimal': result.toString(),
      'hex':
          '0x${result.toRadixString(16).padLeft(width ~/ 4, '0').toUpperCase()}',
      'binary': result.toRadixString(2).padLeft(width, '0'),
    };
  }

  List<DiffPart> diff(String before, String after, {bool byWord = false}) {
    final left = byWord
        ? before.split(RegExp(r'(\s+)'))
        : const LineSplitter().convert(before);
    final right = byWord
        ? after.split(RegExp(r'(\s+)'))
        : const LineSplitter().convert(after);
    final matrix = List.generate(
      left.length + 1,
      (_) => List<int>.filled(right.length + 1, 0),
    );
    for (var i = left.length - 1; i >= 0; i--) {
      for (var j = right.length - 1; j >= 0; j--) {
        matrix[i][j] = left[i] == right[j]
            ? matrix[i + 1][j + 1] + 1
            : (matrix[i + 1][j] > matrix[i][j + 1]
                  ? matrix[i + 1][j]
                  : matrix[i][j + 1]);
      }
    }
    var i = 0;
    var j = 0;
    final result = <DiffPart>[];
    while (i < left.length || j < right.length) {
      if (i < left.length && j < right.length && left[i] == right[j]) {
        result.add(DiffPart(DiffKind.equal, left[i]));
        i++;
        j++;
      } else if (j < right.length &&
          (i == left.length || matrix[i][j + 1] >= matrix[i + 1][j])) {
        result.add(DiffPart(DiffKind.added, right[j++]));
      } else {
        result.add(DiffPart(DiffKind.removed, left[i++]));
      }
    }
    return result;
  }

  String formatCode(String input, String format, {bool compact = false}) {
    switch (format.toLowerCase()) {
      case 'json':
        final value = jsonDecode(input);
        return compact
            ? jsonEncode(value)
            : const JsonEncoder.withIndent('  ').convert(value);
      case 'xml':
        final document = XmlDocument.parse(input);
        return document.toXmlString(pretty: !compact, indent: '  ');
      case 'yaml':
        final value = loadYaml(input);
        return compact
            ? jsonEncode(_yamlToDart(value))
            : _emitYaml(_yamlToDart(value));
      case 'sql':
        return compact
            ? input.replaceAll(RegExp(r'\s+'), ' ').trim()
            : _formatSql(input);
      default:
        throw const FormatException('仅支持 JSON、XML、YAML、SQL');
    }
  }

  BigInt _parseNumber(String input) {
    final text = input.trim().toLowerCase();
    if (text.startsWith('0x'))
      return BigInt.parse(text.substring(2), radix: 16);
    if (text.startsWith('0b')) return BigInt.parse(text.substring(2), radix: 2);
    return BigInt.parse(text);
  }

  Object? _yamlToDart(Object? value) {
    if (value is YamlMap)
      return {
        for (final entry in value.entries)
          entry.key.toString(): _yamlToDart(entry.value),
      };
    if (value is YamlList) return value.map(_yamlToDart).toList();
    return value;
  }

  String _emitYaml(Object? value, [int depth = 0]) {
    final indent = '  ' * depth;
    if (value is Map) {
      return value.entries
          .map((entry) {
            final child = entry.value;
            if (child is Map || child is List)
              return '$indent${entry.key}:\n${_emitYaml(child, depth + 1)}';
            return '$indent${entry.key}: ${_yamlScalar(child)}';
          })
          .join('\n');
    }
    if (value is List) {
      return value
          .map((child) {
            if (child is Map || child is List)
              return '$indent-\n${_emitYaml(child, depth + 1)}';
            return '$indent- ${_yamlScalar(child)}';
          })
          .join('\n');
    }
    return '$indent${_yamlScalar(value)}';
  }

  String _yamlScalar(Object? value) {
    if (value == null) return 'null';
    if (value is num || value is bool) return '$value';
    final text = value.toString();
    return RegExp(r'^[A-Za-z0-9_.\-/]+$').hasMatch(text)
        ? text
        : jsonEncode(text);
  }

  String _formatSql(String input) {
    var sql = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    const keywords = [
      'SELECT',
      'FROM',
      'WHERE',
      'GROUP BY',
      'ORDER BY',
      'HAVING',
      'LIMIT',
      'INSERT INTO',
      'VALUES',
      'UPDATE',
      'SET',
      'DELETE FROM',
      'LEFT JOIN',
      'RIGHT JOIN',
      'INNER JOIN',
      'OUTER JOIN',
      'JOIN',
      'UNION',
    ];
    for (final keyword in keywords) {
      sql = sql.replaceAll(
        RegExp('\\s+${RegExp.escape(keyword)}\\s+', caseSensitive: false),
        '\n$keyword ',
      );
    }
    sql = sql.replaceAllMapped(
      RegExp(r'\s+(AND|OR)\s+', caseSensitive: false),
      (match) => '\n  ${match.group(1)!.toUpperCase()} ',
    );
    return sql.trim();
  }
}
