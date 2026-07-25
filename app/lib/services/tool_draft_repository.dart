import 'dart:async';
import 'dart:convert';

import '../data/app_database.dart';

class DraftPolicy {
  const DraftPolicy({
    this.schemaVersion = 1,
    this.debounce = const Duration(milliseconds: 500),
  });

  final int schemaVersion;
  final Duration debounce;
}

class RestoredToolDraft<T> {
  const RestoredToolDraft({
    required this.scope,
    required this.schemaVersion,
    required this.payload,
    required this.updatedAt,
  });

  final String scope;
  final int schemaVersion;
  final T payload;
  final DateTime updatedAt;
}

/// Persists only non-sensitive, page-level editor state.
///
/// Credentials are deliberately stripped as a second line of defence. Features
/// that explicitly save credentials must continue to use the platform secure
/// store instead of this repository.
class ToolDraftRepository {
  ToolDraftRepository(this._database);

  final AppDatabase _database;
  final Map<String, Timer> _timers = {};
  final Map<String, Map<String, Object?>> _pending = {};

  static final _sensitiveKey = RegExp(
    r'(password|passwd|secret|token|authorization|cookie|private.?key|api.?key)',
    caseSensitive: false,
  );

  Future<RestoredToolDraft<Map<String, Object?>>?> load(
    String scope, {
    DraftPolicy policy = const DraftPolicy(),
  }) async {
    final row = await _database.getToolDraft(scope);
    if (row == null) return null;
    if (row.schemaVersion != policy.schemaVersion) {
      await _database.deleteToolDraft(scope);
      return null;
    }
    try {
      final decoded = jsonDecode(row.payloadJson);
      if (decoded is! Map) return null;
      return RestoredToolDraft(
        scope: scope,
        schemaVersion: row.schemaVersion,
        payload: decoded.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        ),
        updatedAt: row.updatedAt,
      );
    } on Object {
      await _database.deleteToolDraft(scope);
      return null;
    }
  }

  void scheduleSave(
    String scope,
    Map<String, Object?> payload, {
    DraftPolicy policy = const DraftPolicy(),
  }) {
    _pending[scope] = _sanitizeMap(payload);
    _timers.remove(scope)?.cancel();
    _timers[scope] = Timer(policy.debounce, () {
      unawaited(flush(scope, policy: policy));
    });
  }

  Future<void> save(
    String scope,
    Map<String, Object?> payload, {
    DraftPolicy policy = const DraftPolicy(),
  }) async {
    _pending[scope] = _sanitizeMap(payload);
    await flush(scope, policy: policy);
  }

  Future<void> flush(
    String scope, {
    DraftPolicy policy = const DraftPolicy(),
  }) async {
    _timers.remove(scope)?.cancel();
    final payload = _pending.remove(scope);
    if (payload == null) return;
    await _database.putToolDraft(
      ToolDraftsCompanion.insert(
        scope: scope,
        schemaVersion: policy.schemaVersion,
        payloadJson: jsonEncode(payload),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> reset(String scope) async {
    _timers.remove(scope)?.cancel();
    _pending.remove(scope);
    await _database.deleteToolDraft(scope);
  }

  Future<void> clearAll() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _pending.clear();
    await _database.clearToolDrafts();
  }

  Map<String, Object?> _sanitizeMap(Map<String, Object?> value) {
    final semanticName =
        value['name'] ?? value['key'] ?? value['header'] ?? value['field'];
    final isSensitivePair =
        semanticName is String && _sensitiveKey.hasMatch(semanticName);
    final sanitized = <String, Object?>{};
    for (final entry in value.entries) {
      if (_sensitiveKey.hasMatch(entry.key)) continue;
      if (isSensitivePair &&
          const {'value', 'content', 'data', 'text'}.contains(entry.key)) {
        continue;
      }
      sanitized[entry.key] = _sanitizeValue(entry.value);
    }
    return sanitized;
  }

  Object? _sanitizeValue(Object? value) {
    if (value is Map) {
      return _sanitizeMap(
        value.map((key, item) => MapEntry(key.toString(), item as Object?)),
      );
    }
    if (value is List) return value.map(_sanitizeValue).toList(growable: false);
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    return value.toString();
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _pending.clear();
  }
}
