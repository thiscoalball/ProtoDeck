import 'dart:convert';

import 'developer_tools_service.dart';

class IdentifierInspection {
  const IdentifierInspection({
    required this.kind,
    required this.valid,
    required this.fields,
    this.warning,
  });

  final String kind;
  final bool valid;
  final Map<String, String> fields;
  final String? warning;
}

class HttpMetadataInspection {
  const HttpMetadataInspection({
    required this.headers,
    required this.cacheDirectives,
    required this.cookies,
    required this.findings,
  });

  final Map<String, String> headers;
  final Map<String, String> cacheDirectives;
  final List<Map<String, String>> cookies;
  final List<String> findings;
}

class LogInspection {
  const LogInspection({
    required this.total,
    required this.levels,
    required this.traceIds,
    required this.firstTimestamp,
    required this.lastTimestamp,
    required this.normalized,
  });

  final int total;
  final Map<String, int> levels;
  final List<String> traceIds;
  final String? firstTimestamp;
  final String? lastTimestamp;
  final String normalized;
}

class BackendEngineeringService {
  final DeveloperToolsService _developer = DeveloperToolsService();

  String formatSql(String source, {bool compact = false}) =>
      _developer.formatCode(source, 'sql', compact: compact);

  String buildSqlInList(String source, {bool quoteStrings = true}) {
    final values = const LineSplitter()
        .convert(source.replaceAll(',', '\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (values.isEmpty) throw const FormatException('请输入至少一个值');
    String quote(String value) {
      if (!quoteStrings && num.tryParse(value) != null) return value;
      return "'${value.replaceAll("'", "''")}'";
    }

    return '(${values.map(quote).join(', ')})';
  }

  String jsonToInsert(String source, String table) {
    final name = table.trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*$').hasMatch(name)) {
      throw const FormatException('表名只允许字母、数字、下划线和点');
    }
    final decoded = jsonDecode(source);
    final rows = decoded is List ? decoded : [decoded];
    if (rows.isEmpty || rows.any((row) => row is! Map)) {
      throw const FormatException('请输入 JSON Object 或 Object 数组');
    }
    final maps = rows.cast<Map>();
    final columns = <String>[];
    for (final row in maps) {
      for (final key in row.keys.map((key) => key.toString())) {
        if (!columns.contains(key)) columns.add(key);
      }
    }
    String identifier(String value) => '"${value.replaceAll('"', '""')}"';
    String literal(Object? value) => switch (value) {
      null => 'NULL',
      bool value => value ? 'TRUE' : 'FALSE',
      num value => value.toString(),
      _ =>
        "'${(value is String ? value : jsonEncode(value)).replaceAll("'", "''")}'",
    };
    final values = maps
        .map(
          (row) =>
              '(${columns.map((column) => literal(row[column])).join(', ')})',
        )
        .join(',\n  ');
    return 'INSERT INTO ${name.split('.').map(identifier).join('.')} '
        '(${columns.map(identifier).join(', ')})\nVALUES\n  $values;';
  }

  IdentifierInspection inspectIdentifier(
    String source, {
    int snowflakeEpoch = 1288834974657,
    int nodeBits = 10,
    int sequenceBits = 12,
  }) {
    final value = source.trim();
    final compactUuid = value.replaceAll('-', '').toLowerCase();
    if (RegExp(r'^[0-9a-f]{32}$').hasMatch(compactUuid)) {
      final version = int.parse(compactUuid[12], radix: 16);
      final variantNibble = int.parse(compactUuid[16], radix: 16);
      final fields = <String, String>{
        '规范格式':
            '${compactUuid.substring(0, 8)}-${compactUuid.substring(8, 12)}-'
            '${compactUuid.substring(12, 16)}-${compactUuid.substring(16, 20)}-'
            '${compactUuid.substring(20)}',
        '版本': 'UUID v$version',
        'Variant': (variantNibble & 0x8) == 0
            ? 'NCS'
            : (variantNibble & 0xC) == 0x8
            ? 'RFC 4122 / RFC 9562'
            : (variantNibble & 0xE) == 0xC
            ? 'Microsoft'
            : 'Future',
      };
      if (version == 1) {
        final ticks = BigInt.parse(
          '${compactUuid.substring(12, 15)}${compactUuid.substring(8, 12)}${compactUuid.substring(0, 8)}',
          radix: 16,
        );
        final unix100ns = ticks - BigInt.from(0x01B21DD213814000);
        fields['生成时间'] = DateTime.fromMicrosecondsSinceEpoch(
          (unix100ns ~/ BigInt.from(10)).toInt(),
          isUtc: true,
        ).toIso8601String();
      } else if (version == 7) {
        final milliseconds = int.parse(compactUuid.substring(0, 12), radix: 16);
        fields['生成时间'] = DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
          isUtc: true,
        ).toIso8601String();
      }
      return IdentifierInspection(kind: 'UUID', valid: true, fields: fields);
    }

    if (RegExp(
      r'^[0-9A-HJKMNP-TV-Z]{26}$',
      caseSensitive: false,
    ).hasMatch(value)) {
      const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
      var timestamp = BigInt.zero;
      for (final unit in value.substring(0, 10).toUpperCase().codeUnits) {
        timestamp =
            timestamp * BigInt.from(32) +
            BigInt.from(alphabet.indexOf(String.fromCharCode(unit)));
      }
      return IdentifierInspection(
        kind: 'ULID',
        valid: true,
        fields: {
          '生成时间': DateTime.fromMillisecondsSinceEpoch(
            timestamp.toInt(),
            isUtc: true,
          ).toIso8601String(),
          '时间部分': value.substring(0, 10).toUpperCase(),
          '随机部分': value.substring(10).toUpperCase(),
        },
      );
    }

    if (RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(value)) {
      final seconds = int.parse(value.substring(0, 8), radix: 16);
      return IdentifierInspection(
        kind: 'MongoDB ObjectId',
        valid: true,
        fields: {
          '生成时间': DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          ).toIso8601String(),
          '进程随机值': value.substring(8, 18),
          '计数器': int.parse(value.substring(18), radix: 16).toString(),
        },
      );
    }

    final snowflake = BigInt.tryParse(value);
    if (snowflake != null &&
        snowflake >= BigInt.zero &&
        nodeBits + sequenceBits < 63) {
      final sequenceMask = (BigInt.one << sequenceBits) - BigInt.one;
      final nodeMask = (BigInt.one << nodeBits) - BigInt.one;
      final timestamp = snowflake >> (nodeBits + sequenceBits);
      return IdentifierInspection(
        kind: 'Snowflake',
        valid: true,
        fields: {
          '生成时间': DateTime.fromMillisecondsSinceEpoch(
            timestamp.toInt() + snowflakeEpoch,
            isUtc: true,
          ).toIso8601String(),
          '节点 ID': ((snowflake >> sequenceBits) & nodeMask).toString(),
          '序列号': (snowflake & sequenceMask).toString(),
          '自定义 Epoch': snowflakeEpoch.toString(),
        },
        warning: 'Snowflake 没有统一位布局，请核对 Epoch、节点位和序列位。',
      );
    }
    return const IdentifierInspection(
      kind: '未知',
      valid: false,
      fields: {},
      warning: '未识别为 UUID、ULID、ObjectId 或十进制 Snowflake。',
    );
  }

  int compareSemVer(String left, String right) {
    final a = _parseSemVer(left);
    final b = _parseSemVer(right);
    for (var index = 0; index < 3; index++) {
      final compared = a.core[index].compareTo(b.core[index]);
      if (compared != 0) return compared;
    }
    if (a.pre.isEmpty && b.pre.isEmpty) return 0;
    if (a.pre.isEmpty) return 1;
    if (b.pre.isEmpty) return -1;
    final length = a.pre.length > b.pre.length ? a.pre.length : b.pre.length;
    for (var index = 0; index < length; index++) {
      if (index >= a.pre.length) return -1;
      if (index >= b.pre.length) return 1;
      final av = a.pre[index];
      final bv = b.pre[index];
      final ai = int.tryParse(av);
      final bi = int.tryParse(bv);
      final compared = ai != null && bi != null
          ? ai.compareTo(bi)
          : ai != null
          ? -1
          : bi != null
          ? 1
          : av.compareTo(bv);
      if (compared != 0) return compared;
    }
    return 0;
  }

  Map<String, String> inspectSemVer(String source) {
    final value = _parseSemVer(source);
    return {
      '规范版本':
          '${value.core.join('.')}${value.pre.isEmpty ? '' : '-${value.pre.join('.')}'}'
          '${value.build.isEmpty ? '' : '+${value.build.join('.')}'}',
      '主版本': value.core[0].toString(),
      '次版本': value.core[1].toString(),
      '修订号': value.core[2].toString(),
      '预发布': value.pre.isEmpty ? '无' : value.pre.join('.'),
      '构建元数据': value.build.isEmpty ? '无' : value.build.join('.'),
      '稳定版本': value.pre.isEmpty ? '是' : '否',
    };
  }

  HttpMetadataInspection inspectHttpHeaders(String source) {
    final headers = <String, String>{};
    final cookies = <Map<String, String>>[];
    for (final raw in const LineSplitter().convert(source)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('HTTP/')) continue;
      final split = line.indexOf(':');
      if (split <= 0) continue;
      final key = line.substring(0, split).trim();
      final value = line.substring(split + 1).trim();
      if (key.toLowerCase() == 'set-cookie') {
        cookies.add(_parseCookie(value));
      } else {
        headers[key] = headers.containsKey(key)
            ? '${headers[key]}, $value'
            : value;
      }
    }
    final normalized = {
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
    final cache = <String, String>{};
    for (final part in (normalized['cache-control'] ?? '').split(',')) {
      if (part.trim().isEmpty) continue;
      final split = part.indexOf('=');
      cache[split < 0
          ? part.trim()
          : part.substring(0, split).trim()] = split < 0
          ? 'true'
          : part.substring(split + 1).trim().replaceAll('"', '');
    }
    final findings = <String>[];
    if (cache.containsKey('no-store')) findings.add('响应不得进入任何缓存。');
    if (cache.containsKey('private')) findings.add('只允许私有缓存保存响应。');
    if (cache.containsKey('public')) findings.add('响应允许共享缓存。');
    if (cache['max-age'] != null) findings.add('浏览器新鲜期 ${cache['max-age']} 秒。');
    if (cache['s-maxage'] != null)
      findings.add('共享缓存新鲜期 ${cache['s-maxage']} 秒。');
    if (normalized['access-control-allow-origin'] == '*' &&
        normalized['access-control-allow-credentials'] == 'true') {
      findings.add('CORS 配置冲突：携带凭据时不能使用通配 Origin。');
    }
    if (normalized['content-security-policy'] == null)
      findings.add('未发现 Content-Security-Policy。');
    if (normalized['strict-transport-security'] == null)
      findings.add('未发现 HSTS；仅 HTTPS 站点需要。');
    final contentType = normalized['content-type'];
    if (contentType != null) findings.add('响应媒体类型：$contentType');
    return HttpMetadataInspection(
      headers: headers,
      cacheDirectives: cache,
      cookies: cookies,
      findings: findings,
    );
  }

  LogInspection inspectLogs(String source) {
    final levels = <String, int>{};
    final traces = <String>{};
    final timestamps = <String>[];
    final normalized = <String>[];
    final ansi = RegExp(r'\x1B(?:[@-_]|\[[0-?]*[ -/]*[@-~])');
    final tracePattern = RegExp(
      r'(?:trace[_-]?id|request[_-]?id|correlation[_-]?id)[=:"\s]+([0-9a-zA-Z_-]{8,64})',
      caseSensitive: false,
    );
    final timePattern = RegExp(
      r'\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?\b',
    );
    for (final raw in const LineSplitter().convert(source)) {
      if (raw.trim().isEmpty) continue;
      final line = raw.replaceAll(ansi, '');
      normalized.add(line);
      String level = 'OTHER';
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          final candidate =
              decoded['level'] ?? decoded['severity'] ?? decoded['logLevel'];
          if (candidate != null) level = candidate.toString().toUpperCase();
          final trace =
              decoded['traceId'] ?? decoded['trace_id'] ?? decoded['requestId'];
          if (trace != null) traces.add(trace.toString());
          final time =
              decoded['timestamp'] ?? decoded['time'] ?? decoded['@timestamp'];
          if (time != null) timestamps.add(time.toString());
        }
      } on FormatException {
        final levelMatch = RegExp(
          r'\b(TRACE|DEBUG|INFO|NOTICE|WARN(?:ING)?|ERROR|FATAL|CRITICAL)\b',
          caseSensitive: false,
        ).firstMatch(line);
        if (levelMatch != null) level = levelMatch.group(1)!.toUpperCase();
      }
      levels[level] = (levels[level] ?? 0) + 1;
      final trace = tracePattern.firstMatch(line)?.group(1);
      if (trace != null) traces.add(trace);
      final time = timePattern.firstMatch(line)?.group(0);
      if (time != null) timestamps.add(time);
    }
    return LogInspection(
      total: normalized.length,
      levels: levels,
      traceIds: traces.toList()..sort(),
      firstTimestamp: timestamps.isEmpty ? null : timestamps.first,
      lastTimestamp: timestamps.isEmpty ? null : timestamps.last,
      normalized: normalized.join('\n'),
    );
  }

  Map<String, String> _parseCookie(String value) {
    final parts = value.split(';').map((item) => item.trim()).toList();
    final output = <String, String>{};
    for (var index = 0; index < parts.length; index++) {
      final split = parts[index].indexOf('=');
      if (index == 0) {
        output['name'] = split < 0
            ? parts[index]
            : parts[index].substring(0, split);
        output['value'] = split < 0 ? '' : parts[index].substring(split + 1);
      } else {
        output[split < 0 ? parts[index] : parts[index].substring(0, split)] =
            split < 0 ? 'true' : parts[index].substring(split + 1);
      }
    }
    return output;
  }

  _SemVerValue _parseSemVer(String source) {
    final match = RegExp(
      r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
      r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
      r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
    ).firstMatch(source.trim());
    if (match == null) throw const FormatException('不是有效的 Semantic Version');
    final pre = match.group(4)?.split('.') ?? const <String>[];
    if (pre.any(
      (item) =>
          item.length > 1 && item.startsWith('0') && int.tryParse(item) != null,
    )) {
      throw const FormatException('预发布数字标识符不能包含前导零');
    }
    return _SemVerValue(
      [
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      ],
      pre,
      match.group(5)?.split('.') ?? const <String>[],
    );
  }
}

class _SemVerValue {
  const _SemVerValue(this.core, this.pre, this.build);
  final List<int> core;
  final List<String> pre;
  final List<String> build;
}
