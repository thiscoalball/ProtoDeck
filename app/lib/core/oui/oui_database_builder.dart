import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

typedef OuiProgressCallback = void Function(String message, double progress);

class OuiSource {
  const OuiSource({
    required this.registry,
    required this.prefixLength,
    required this.url,
    required this.minimumRecords,
  });

  final String registry;
  final int prefixLength;
  final Uri url;
  final int minimumRecords;

  String get fileName => switch (prefixLength) {
    24 => 'oui.csv',
    28 => 'mam.csv',
    36 => 'oui36.csv',
    _ => '$registry.csv',
  };
}

final ieeeOuiSources = [
  OuiSource(
    registry: 'MA-L',
    prefixLength: 24,
    url: Uri.parse('https://standards-oui.ieee.org/oui/oui.csv'),
    minimumRecords: 35000,
  ),
  OuiSource(
    registry: 'MA-M',
    prefixLength: 28,
    url: Uri.parse('https://standards-oui.ieee.org/oui28/mam.csv'),
    minimumRecords: 5500,
  ),
  OuiSource(
    registry: 'MA-S',
    prefixLength: 36,
    url: Uri.parse('https://standards-oui.ieee.org/oui36/oui36.csv'),
    minimumRecords: 6000,
  ),
];

class OuiBuildResult {
  const OuiBuildResult({
    required this.outputPath,
    required this.counts,
    this.changed = true,
  });

  final String outputPath;
  final Map<String, int> counts;
  final bool changed;

  int get totalRecords => counts.values.fold(0, (sum, value) => sum + value);
}

class OuiDatabaseBuilder {
  OuiDatabaseBuilder({http.Client? client}) : _client = client ?? http.Client();

  static const expectedHeader = [
    'Registry',
    'Assignment',
    'Organization Name',
    'Organization Address',
  ];

  final http.Client _client;

  Future<OuiBuildResult> downloadAndBuild({
    required Directory cacheDirectory,
    required File outputFile,
    File? previousDatabase,
    OuiProgressCallback? onProgress,
  }) async {
    await cacheDirectory.create(recursive: true);
    await outputFile.parent.create(recursive: true);
    final previousMetadata = _readPreviousMetadata(previousDatabase);
    final downloads = <_DownloadedOui>[];
    var anyChanged = false;
    for (var index = 0; index < ieeeOuiSources.length; index++) {
      final source = ieeeOuiSources[index];
      onProgress?.call(
        '正在下载 ${source.registry}',
        index / (ieeeOuiSources.length + 1),
      );
      final cacheFile = File(p.join(cacheDirectory.path, source.fileName));
      final old = previousMetadata[source.registry];
      final headers = <String, String>{
        'User-Agent': 'curl/8.5.0',
        'Accept': 'text/csv,application/octet-stream,*/*',
      };
      if (cacheFile.existsSync()) {
        if (old?.etag case final etag?) headers['If-None-Match'] = etag;
        if (old?.lastModified case final modified?) {
          headers['If-Modified-Since'] = modified;
        }
      }
      final response = await _client
          .get(source.url, headers: headers)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == HttpStatus.notModified &&
          cacheFile.existsSync() &&
          old != null) {
        final bytes = await cacheFile.readAsBytes();
        downloads.add(
          _DownloadedOui(
            source: source,
            bytes: bytes,
            etag: old.etag,
            lastModified: old.lastModified,
            sha256Hex: sha256.convert(bytes).toString(),
          ),
        );
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          '${source.registry} 下载失败：HTTP ${response.statusCode}',
          uri: source.url,
        );
      }
      if (response.bodyBytes.length > 12 * 1024 * 1024) {
        throw const FormatException('IEEE OUI 响应异常：文件超过 12 MiB');
      }
      await cacheFile.writeAsBytes(response.bodyBytes, flush: true);
      anyChanged = true;
      downloads.add(
        _DownloadedOui(
          source: source,
          bytes: response.bodyBytes,
          etag: response.headers['etag'],
          lastModified: response.headers['last-modified'],
          sha256Hex: sha256.convert(response.bodyBytes).toString(),
        ),
      );
    }

    if (!anyChanged && previousMetadata.length == ieeeOuiSources.length) {
      onProgress?.call('OUI 数据库已是最新', 1);
      return OuiBuildResult(
        outputPath: outputFile.path,
        counts: {
          for (final entry in previousMetadata.entries)
            entry.key: entry.value.count,
        },
        changed: false,
      );
    }

    onProgress?.call('正在解析 IEEE 数据', 0.72);
    final parsed = downloads.map(_parse).toList(growable: false);
    _validateAgainstPrevious(parsed, previousDatabase);
    final result = await _writeDatabase(
      parsed: parsed,
      outputFile: outputFile,
      onProgress: onProgress,
    );
    onProgress?.call('OUI 数据库已生成', 1);
    return result;
  }

  Map<String, _PreviousOuiMetadata> _readPreviousMetadata(File? file) {
    if (file == null || !file.existsSync()) return const {};
    Database? database;
    try {
      database = sqlite3.open(file.path, mode: OpenMode.readOnly);
      final rows = database.select(
        'SELECT source_name, source_etag, source_last_modified, record_count '
        'FROM oui_metadata',
      );
      return {
        for (final row in rows)
          row['source_name'] as String: _PreviousOuiMetadata(
            etag: row['source_etag'] as String?,
            lastModified: row['source_last_modified'] as String?,
            count: row['record_count'] as int,
          ),
      };
    } on SqliteException {
      return const {};
    } finally {
      database?.close();
    }
  }

  _ParsedOui _parse(_DownloadedOui download) {
    final text = utf8.decode(download.bytes, allowMalformed: false);
    final rows = Csv(dynamicTyping: false, lineDelimiter: '\n').decode(text);
    if (rows.isEmpty) {
      throw FormatException('${download.source.registry} CSV 为空');
    }
    final header = rows.first.map((cell) => cell.toString().trim()).toList();
    if (header.length < expectedHeader.length ||
        !Iterable<int>.generate(
          expectedHeader.length,
        ).every((index) => header[index] == expectedHeader[index])) {
      throw FormatException('${download.source.registry} CSV 表头不匹配');
    }

    final records = <_OuiRecord>[];
    final seenRows = <String>{};
    for (var index = 1; index < rows.length; index++) {
      final row = rows[index];
      if (row.length < 3 ||
          row.every((cell) => cell.toString().trim().isEmpty)) {
        continue;
      }
      final registry = row[0].toString().trim().replaceFirst('\ufeff', '');
      final assignment = row[1].toString().trim().toUpperCase();
      if (registry != download.source.registry) {
        throw FormatException(
          '${download.source.registry} 第 ${index + 1} 行 Registry 异常：$registry',
        );
      }
      if (assignment.length != download.source.prefixLength ~/ 4 ||
          !RegExp(r'^[0-9A-F]+$').hasMatch(assignment)) {
        throw FormatException(
          '${download.source.registry} 第 ${index + 1} 行前缀异常：$assignment',
        );
      }
      final prefix = int.parse(assignment, radix: 16);
      final organizationName = row[2].toString().trim();
      final organizationAddress = row.length > 3
          ? row[3].toString().trim()
          : '';
      final rowKey =
          '$assignment\u0000$organizationName\u0000$organizationAddress';
      if (!seenRows.add(rowKey)) continue;
      records.add(
        _OuiRecord(
          prefixValue: prefix,
          prefixLength: download.source.prefixLength,
          registry: registry,
          assignment: assignment,
          organizationName: organizationName,
          organizationAddress: organizationAddress,
        ),
      );
    }
    if (records.length < download.source.minimumRecords) {
      throw FormatException(
        '${download.source.registry} 只有 ${records.length} 条，低于安全阈值 '
        '${download.source.minimumRecords}',
      );
    }
    return _ParsedOui(download: download, records: records);
  }

  void _validateAgainstPrevious(
    List<_ParsedOui> parsed,
    File? previousDatabase,
  ) {
    if (previousDatabase == null || !previousDatabase.existsSync()) return;
    Database? database;
    try {
      database = sqlite3.open(previousDatabase.path, mode: OpenMode.readOnly);
      for (final data in parsed) {
        final row = database.select(
          'SELECT COUNT(*) AS count FROM oui_prefix WHERE registry = ?',
          [data.download.source.registry],
        ).first;
        final oldCount = row['count'] as int;
        if (oldCount > 0 && data.records.length < oldCount * 0.95) {
          throw FormatException(
            '${data.download.source.registry} 记录数从 $oldCount 异常下降到 '
            '${data.records.length}',
          );
        }
      }
    } on SqliteException {
      // Older or invalid databases are ignored; absolute thresholds still apply.
    } finally {
      database?.close();
    }
  }

  Future<OuiBuildResult> _writeDatabase({
    required List<_ParsedOui> parsed,
    required File outputFile,
    OuiProgressCallback? onProgress,
  }) async {
    final next = File('${outputFile.path}.next');
    if (next.existsSync()) next.deleteSync();
    final database = sqlite3.open(next.path);
    try {
      database.execute('PRAGMA journal_mode = OFF');
      database.execute('PRAGMA synchronous = OFF');
      database.execute('''
        CREATE TABLE oui_prefix (
          id INTEGER PRIMARY KEY,
          prefix_value INTEGER NOT NULL,
          prefix_length INTEGER NOT NULL,
          registry TEXT NOT NULL,
          assignment TEXT NOT NULL,
          organization_name TEXT NOT NULL,
          organization_address TEXT
        )
      ''');
      database.execute('''
        CREATE INDEX oui_prefix_lookup
        ON oui_prefix(prefix_length, prefix_value)
      ''');
      database.execute('''
        CREATE INDEX oui_organization_name_lookup
        ON oui_prefix(organization_name COLLATE NOCASE)
      ''');
      database.execute('''
        CREATE TABLE oui_metadata (
          schema_version INTEGER NOT NULL,
          generated_at INTEGER NOT NULL,
          source_name TEXT NOT NULL,
          source_url TEXT NOT NULL,
          source_etag TEXT,
          source_last_modified TEXT,
          source_sha256 TEXT NOT NULL,
          record_count INTEGER NOT NULL
        )
      ''');

      database.execute('BEGIN IMMEDIATE');
      final insertRecord = database.prepare('''
        INSERT INTO oui_prefix(
          prefix_value, prefix_length, registry, assignment,
          organization_name, organization_address
        ) VALUES (?, ?, ?, ?, ?, ?)
      ''');
      final insertMetadata = database.prepare('''
        INSERT INTO oui_metadata VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      try {
        var completed = 0;
        final total = parsed.fold<int>(
          0,
          (sum, item) => sum + item.records.length,
        );
        final generatedAt = DateTime.now().millisecondsSinceEpoch;
        for (final data in parsed) {
          for (final record in data.records) {
            insertRecord.execute([
              record.prefixValue,
              record.prefixLength,
              record.registry,
              record.assignment,
              record.organizationName,
              record.organizationAddress,
            ]);
            completed++;
            if (completed % 3000 == 0) {
              onProgress?.call(
                '正在写入 OUI 数据 $completed / $total',
                0.75 + (completed / total) * 0.2,
              );
            }
          }
          final source = data.download.source;
          insertMetadata.execute([
            1,
            generatedAt,
            source.registry,
            source.url.toString(),
            data.download.etag,
            data.download.lastModified,
            data.download.sha256Hex,
            data.records.length,
          ]);
        }
        database.execute('COMMIT');
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      } finally {
        insertRecord.close();
        insertMetadata.close();
      }

      final integrity = database
          .select('PRAGMA integrity_check')
          .first
          .values
          .first;
      if (integrity != 'ok') {
        throw StateError('OUI SQLite 完整性检查失败：$integrity');
      }
      for (final parsedSource in parsed) {
        final sample = parsedSource.records[parsedSource.records.length ~/ 2];
        final found = database.select(
          'SELECT organization_name FROM oui_prefix '
          'WHERE prefix_length = ? AND prefix_value = ?',
          [sample.prefixLength, sample.prefixValue],
        );
        if (found.length != 1) throw StateError('OUI SQLite 抽样查询失败');
      }
    } finally {
      database.close();
    }

    final backup = File('${outputFile.path}.backup');
    if (backup.existsSync()) backup.deleteSync();
    if (outputFile.existsSync()) await outputFile.rename(backup.path);
    try {
      await next.rename(outputFile.path);
      if (backup.existsSync()) await backup.delete();
    } catch (_) {
      if (backup.existsSync() && !outputFile.existsSync()) {
        await backup.rename(outputFile.path);
      }
      rethrow;
    }
    return OuiBuildResult(
      outputPath: outputFile.path,
      counts: {
        for (final item in parsed)
          item.download.source.registry: item.records.length,
      },
    );
  }

  void close() => _client.close();
}

class _PreviousOuiMetadata {
  const _PreviousOuiMetadata({
    required this.etag,
    required this.lastModified,
    required this.count,
  });

  final String? etag;
  final String? lastModified;
  final int count;
}

class _DownloadedOui {
  const _DownloadedOui({
    required this.source,
    required this.bytes,
    required this.etag,
    required this.lastModified,
    required this.sha256Hex,
  });

  final OuiSource source;
  final List<int> bytes;
  final String? etag;
  final String? lastModified;
  final String sha256Hex;
}

class _ParsedOui {
  const _ParsedOui({required this.download, required this.records});

  final _DownloadedOui download;
  final List<_OuiRecord> records;
}

class _OuiRecord {
  const _OuiRecord({
    required this.prefixValue,
    required this.prefixLength,
    required this.registry,
    required this.assignment,
    required this.organizationName,
    required this.organizationAddress,
  });

  final int prefixValue;
  final int prefixLength;
  final String registry;
  final String assignment;
  final String organizationName;
  final String organizationAddress;
}
