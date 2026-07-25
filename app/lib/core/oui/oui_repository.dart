import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'oui_database_builder.dart';

class OuiMatch {
  const OuiMatch({
    required this.normalizedMac,
    required this.prefixLength,
    required this.registry,
    required this.assignment,
    required this.organizationName,
    required this.organizationAddress,
    required this.isLocallyAdministered,
    required this.isMulticast,
    this.alternativeOrganizations = const [],
  });

  final String normalizedMac;
  final int prefixLength;
  final String registry;
  final String assignment;
  final String organizationName;
  final String organizationAddress;
  final bool isLocallyAdministered;
  final bool isMulticast;
  final List<String> alternativeOrganizations;
}

class OuiDatabaseMetadata {
  const OuiDatabaseMetadata({
    required this.generatedAt,
    required this.counts,
    required this.lastModified,
    required this.fileSize,
  });

  final DateTime generatedAt;
  final Map<String, int> counts;
  final Map<String, String?> lastModified;
  final int fileSize;

  int get totalRecords => counts.values.fold(0, (sum, value) => sum + value);
}

class OuiOrganizationPrefix {
  const OuiOrganizationPrefix({
    required this.registry,
    required this.assignment,
    required this.prefixLength,
    required this.prefixValue,
    required this.organizationName,
    required this.organizationAddress,
  });

  final String registry;
  final String assignment;
  final int prefixLength;
  final int prefixValue;
  final String organizationName;
  final String organizationAddress;

  String get formattedPrefix => '${_formatMacHex(_startValue)}/$prefixLength';
  String get firstAddress => _formatMacHex(_startValue);
  String get lastAddress => _formatMacHex(_endValue);

  int get _remainingBits => 48 - prefixLength;
  int get _startValue => prefixValue << _remainingBits;
  int get _endValue => _startValue | ((1 << _remainingBits) - 1);

  static String _formatMacHex(int value) {
    final hex = value.toRadixString(16).padLeft(12, '0').toUpperCase();
    return [
      for (var index = 0; index < 12; index += 2)
        hex.substring(index, index + 2),
    ].join(':');
  }
}

class OuiOrganizationSearchResult {
  const OuiOrganizationSearchResult({
    required this.query,
    required this.totalMatches,
    required this.items,
  });

  final String query;
  final int totalMatches;
  final List<OuiOrganizationPrefix> items;

  bool get truncated => totalMatches > items.length;
}

class OuiRepository {
  static const assetPath = 'assets/data/ieee_oui.db';

  Database? _database;
  File? _databaseFile;
  Directory? _baseDirectory;

  Future<void> initialize() async {
    final appSupport = await getApplicationSupportDirectory();
    _baseDirectory = Directory(p.join(appSupport.path, 'oui'));
    await _baseDirectory!.create(recursive: true);
    _databaseFile = File(p.join(_baseDirectory!.path, 'ieee_oui.db'));
    if (!await _databaseFile!.exists()) {
      await _copyBundledDatabase(_databaseFile!);
    }
    _open();
  }

  OuiMatch? lookup(String input) {
    final database = _requireDatabase();
    final hex = input.replaceAll(RegExp(r'[:.\-\s]'), '').toUpperCase();
    if (hex.length != 12 || !RegExp(r'^[0-9A-F]{12}$').hasMatch(hex)) {
      throw const FormatException('请输入 48 位 MAC，例如 AA:BB:CC:DD:EE:FF');
    }
    final mac = int.parse(hex, radix: 16);
    for (final length in const [36, 28, 24]) {
      final prefix = mac >> (48 - length);
      final rows = database.select(
        'SELECT registry, assignment, organization_name, organization_address '
        'FROM oui_prefix WHERE prefix_length = ? AND prefix_value = ? '
        'ORDER BY id',
        [length, prefix],
      );
      if (rows.isEmpty) continue;
      final first = rows.first;
      return OuiMatch(
        normalizedMac: _formatMac(hex),
        prefixLength: length,
        registry: first['registry'] as String,
        assignment: first['assignment'] as String,
        organizationName: first['organization_name'] as String,
        organizationAddress: first['organization_address'] as String? ?? '',
        isLocallyAdministered:
            (int.parse(hex.substring(0, 2), radix: 16) & 2) != 0,
        isMulticast: (int.parse(hex.substring(0, 2), radix: 16) & 1) != 0,
        alternativeOrganizations: rows
            .skip(1)
            .map((row) => row['organization_name'] as String)
            .where((name) => name != first['organization_name'])
            .toSet()
            .toList(growable: false),
      );
    }
    return null;
  }

  OuiOrganizationSearchResult searchOrganizations(
    String input, {
    int limit = 200,
  }) {
    final database = _requireDatabase();
    final query = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.length < 2) {
      throw const FormatException('请输入至少 2 个字符的厂商名称');
    }
    final safeLimit = limit.clamp(1, 500);
    final escaped = query
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final containsPattern = '%$escaped%';
    final prefixPattern = '$escaped%';
    final total =
        database.select(
              "SELECT COUNT(*) AS count FROM oui_prefix "
              "WHERE organization_name LIKE ? ESCAPE '\\' COLLATE NOCASE",
              [containsPattern],
            ).first['count']
            as int;
    final rows = database.select(
      '''
      SELECT registry, assignment, prefix_length, prefix_value,
             organization_name, organization_address,
             CASE
               WHEN organization_name = ? COLLATE NOCASE THEN 0
               WHEN organization_name LIKE ? ESCAPE '\\' COLLATE NOCASE THEN 1
               ELSE 2
             END AS match_rank
      FROM oui_prefix
      WHERE organization_name LIKE ? ESCAPE '\\' COLLATE NOCASE
      ORDER BY match_rank, organization_name COLLATE NOCASE,
               prefix_length DESC, assignment
      LIMIT ?
      ''',
      [query, prefixPattern, containsPattern, safeLimit],
    );
    return OuiOrganizationSearchResult(
      query: query,
      totalMatches: total,
      items: rows
          .map(
            (row) => OuiOrganizationPrefix(
              registry: row['registry'] as String,
              assignment: row['assignment'] as String,
              prefixLength: row['prefix_length'] as int,
              prefixValue: row['prefix_value'] as int,
              organizationName: row['organization_name'] as String,
              organizationAddress: row['organization_address'] as String? ?? '',
            ),
          )
          .toList(growable: false),
    );
  }

  OuiDatabaseMetadata metadata() {
    final database = _requireDatabase();
    final rows = database.select(
      'SELECT generated_at, source_name, source_last_modified, record_count '
      'FROM oui_metadata ORDER BY source_name',
    );
    if (rows.isEmpty) throw StateError('OUI 元数据缺失');
    return OuiDatabaseMetadata(
      generatedAt: DateTime.fromMillisecondsSinceEpoch(
        rows
            .map((row) => row['generated_at'] as int)
            .reduce((left, right) => left > right ? left : right),
      ),
      counts: {
        for (final row in rows)
          row['source_name'] as String: row['record_count'] as int,
      },
      lastModified: {
        for (final row in rows)
          row['source_name'] as String: row['source_last_modified'] as String?,
      },
      fileSize: _databaseFile!.lengthSync(),
    );
  }

  Future<OuiBuildResult> update({OuiProgressCallback? onProgress}) async {
    final output = _databaseFile!;
    final builder = OuiDatabaseBuilder();
    _closeDatabase();
    try {
      final result = await builder.downloadAndBuild(
        cacheDirectory: Directory(p.join(_baseDirectory!.path, 'staging')),
        outputFile: output,
        previousDatabase: output.existsSync() ? output : null,
        onProgress: onProgress,
      );
      _open();
      return result;
    } catch (_) {
      _open();
      rethrow;
    } finally {
      builder.close();
    }
  }

  Future<void> restoreBundled() async {
    _closeDatabase();
    final restore = File('${_databaseFile!.path}.restore');
    await _copyBundledDatabase(restore);
    final backup = File('${_databaseFile!.path}.backup');
    if (await backup.exists()) await backup.delete();
    if (await _databaseFile!.exists()) await _databaseFile!.rename(backup.path);
    try {
      await restore.rename(_databaseFile!.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await _databaseFile!.exists()) {
        await backup.rename(_databaseFile!.path);
      }
      rethrow;
    } finally {
      _open();
    }
  }

  Future<void> _copyBundledDatabase(File target) async {
    await target.parent.create(recursive: true);
    final data = await rootBundle.load(assetPath);
    final bytes = Uint8List.sublistView(data);
    await target.writeAsBytes(bytes, flush: true);
  }

  void _open() {
    _closeDatabase();
    _database = sqlite3.open(_databaseFile!.path);
    final integrity = _database!
        .select('PRAGMA quick_check')
        .first
        .values
        .first;
    if (integrity != 'ok') {
      _closeDatabase();
      throw StateError('OUI 数据库损坏：$integrity');
    }
    _database!.execute('''
      CREATE INDEX IF NOT EXISTS oui_organization_name_lookup
      ON oui_prefix(organization_name COLLATE NOCASE)
    ''');
  }

  Database _requireDatabase() {
    final database = _database;
    if (database == null) throw StateError('OUI 数据库尚未初始化');
    return database;
  }

  String _formatMac(String hex) => [
    for (var index = 0; index < 12; index += 2) hex.substring(index, index + 2),
  ].join(':');

  void _closeDatabase() {
    _database?.close();
    _database = null;
  }

  void dispose() => _closeDatabase();
}
