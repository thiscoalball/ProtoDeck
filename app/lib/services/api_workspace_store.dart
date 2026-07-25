import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_workspace.dart';

/// Small persistence boundary for the API workbench.
///
/// Request bodies and non-sensitive configuration stay in SharedPreferences so
/// they work consistently on every supported platform. Passwords and tokens
/// are kept separately in the platform secure store and never mixed into the
/// exported template JSON.
class ApiWorkspaceStore {
  ApiWorkspaceStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static String draftKey(String workspace) =>
      'api_workspace_draft_v1_$workspace';
  static String templatesKey(String workspace) =>
      'api_workspace_templates_v1_$workspace';
  static String messageTemplatesKey(String workspace) =>
      'api_workspace_message_templates_v1_$workspace';
  static String sentHistoryKey(String workspace) =>
      'api_workspace_sent_history_v1_$workspace';
  static const environmentsKey = 'api_workspace_environments_v1';
  static const activeEnvironmentKey = 'api_workspace_active_environment_v1';
  static const _workspaceProtocols = ['rest', 'websocket', 'sse', 'mqtt'];

  /// Exports only portable, non-sensitive workspace data. Secure-storage values,
  /// active sockets, response bodies and sent-message history are intentionally
  /// excluded.
  Future<Map<String, Object?>> exportWorkspace() async {
    final collections = <String, Object?>{};
    final messageTemplates = <String, Object?>{};
    for (final protocol in _workspaceProtocols) {
      collections[protocol] = await loadList(templatesKey(protocol));
      if (protocol != 'rest') {
        messageTemplates[protocol] = await loadList(
          messageTemplatesKey(protocol),
        );
      }
    }
    final environments = await loadEnvironments();
    return {
      'format': 'protodeck-api-workspace',
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'collections': collections,
      'messageTemplates': messageTemplates,
      'environments': environments.map((item) => item.toJson()).toList(),
    };
  }

  Future<void> importWorkspace(
    Map<String, Object?> bundle, {
    required bool replace,
  }) async {
    if (bundle['format'] != 'protodeck-api-workspace' ||
        (bundle['schemaVersion'] as num?)?.toInt() != 1) {
      throw const FormatException('不是受支持的 ProtoDeck API 工作区文件');
    }
    final collections = _stringMap(bundle['collections']);
    final messages = _stringMap(bundle['messageTemplates']);
    for (final protocol in _workspaceProtocols) {
      final imported = _mapList(collections[protocol]);
      final next = replace
          ? imported
          : _mergeById(await loadList(templatesKey(protocol)), imported);
      await saveList(templatesKey(protocol), next);
      if (protocol != 'rest') {
        final importedMessages = _mapList(messages[protocol]);
        final nextMessages = replace
            ? importedMessages
            : _mergeById(
                await loadList(messageTemplatesKey(protocol)),
                importedMessages,
              );
        await saveList(messageTemplatesKey(protocol), nextMessages);
      }
    }
    final importedEnvironments = _mapList(bundle['environments'])
        .map(
          (row) => ApiEnvironmentProfile(
            id: row['id']?.toString() ?? '',
            name: row['name']?.toString() ?? 'Environment',
            variables: _mapList(row['variables'])
                .where((item) => item['name']?.toString().isNotEmpty == true)
                .map((item) => ApiEnvironmentVariable.fromJson(item))
                .toList(),
          ),
        )
        .where((item) => item.id.isNotEmpty)
        .toList();
    if (importedEnvironments.isNotEmpty) {
      final environments = replace
          ? importedEnvironments
          : _mergeEnvironments(await loadEnvironments(), importedEnvironments);
      await saveEnvironments(environments);
    }
  }

  Future<Map<String, Object?>?> loadMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final value = jsonDecode(encoded);
      return value is Map
          ? value.map((key, value) => MapEntry(key.toString(), value))
          : null;
    } on Object {
      return null;
    }
  }

  Future<void> saveMap(String key, Map<String, Object?> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<List<Map<String, Object?>>> loadList(
    String key, {
    String? legacyKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded =
        prefs.getString(key) ??
        (legacyKey == null ? null : prefs.getString(legacyKey));
    // Callers use the returned collection as an editor model (insert, update,
    // delete). Always return a growable list, including the empty and corrupt
    // cases; `const []` makes the first Save action throw at List.insert().
    if (encoded == null || encoded.isEmpty) return <Map<String, Object?>>[];
    try {
      final value = jsonDecode(encoded);
      if (value is! List) return <Map<String, Object?>>[];
      return value
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList();
    } on Object {
      return <Map<String, Object?>>[];
    }
  }

  Future<void> saveList(String key, List<Map<String, Object?>> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(values));
  }

  Future<Map<String, String>> loadSecrets(String scope) async {
    try {
      final encoded = await _secureStorage.read(key: _secretKey(scope));
      if (encoded == null || encoded.isEmpty) return const {};
      final value = jsonDecode(encoded);
      if (value is! Map) return const {};
      return value.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
    } on Object {
      // Secure storage can be unavailable in tests or on a minimal Linux
      // desktop. The non-sensitive workspace must remain usable regardless.
      return const {};
    }
  }

  Future<void> saveSecrets(String scope, Map<String, String> values) async {
    try {
      if (values.values.every((value) => value.isEmpty)) {
        await _secureStorage.delete(key: _secretKey(scope));
      } else {
        await _secureStorage.write(
          key: _secretKey(scope),
          value: jsonEncode(values),
        );
      }
    } on Object {
      // See loadSecrets: persistence of ordinary request data still succeeds.
    }
  }

  Future<void> deleteSecrets(String scope) async {
    try {
      await _secureStorage.delete(key: _secretKey(scope));
    } on Object {
      // Nothing else needs to be deleted when the platform store is absent.
    }
  }

  Future<List<ApiEnvironmentProfile>> loadEnvironments() async {
    final rows = await loadList(environmentsKey);
    if (rows.isEmpty) {
      return const [
        ApiEnvironmentProfile(
          id: 'default',
          name: 'Default',
          variables: [ApiEnvironmentVariable(name: 'name', value: 'ProtoDeck')],
        ),
      ];
    }
    final result = <ApiEnvironmentProfile>[];
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final secrets = await loadSecrets('environment_$id');
      final variables = (row['variables'] as List<Object?>? ?? const [])
          .whereType<Map>()
          .map((item) {
            final normalized = item.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            final name = normalized['name']?.toString() ?? '';
            return ApiEnvironmentVariable.fromJson(
              normalized,
              secretValue: secrets[name],
            );
          })
          .toList();
      result.add(
        ApiEnvironmentProfile(
          id: id,
          name: row['name']?.toString() ?? 'Environment',
          variables: variables,
        ),
      );
    }
    return result;
  }

  Future<void> saveEnvironments(List<ApiEnvironmentProfile> values) async {
    await saveList(
      environmentsKey,
      values.map((item) => item.toJson()).toList(),
    );
    for (final environment in values) {
      await saveSecrets('environment_${environment.id}', {
        for (final variable in environment.variables)
          if (variable.secret && variable.name.trim().isNotEmpty)
            variable.name.trim(): variable.value,
      });
    }
  }

  Future<String?> loadActiveEnvironmentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(activeEnvironmentKey);
  }

  Future<void> saveActiveEnvironmentId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(activeEnvironmentKey, id);
  }

  static String _secretKey(String scope) => 'api_workspace_secret_v1_$scope';

  static Map<String, Object?> _stringMap(Object? value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : const {};

  static List<Map<String, Object?>> _mapList(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map(
              (item) => item.map(
                (key, entry) => MapEntry(key.toString(), entry as Object?),
              ),
            )
            .toList()
      : <Map<String, Object?>>[];

  static List<Map<String, Object?>> _mergeById(
    List<Map<String, Object?>> current,
    List<Map<String, Object?>> imported,
  ) {
    final result = <String, Map<String, Object?>>{};
    for (final row in [...current, ...imported]) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      result[id] = row;
    }
    return result.values.toList();
  }

  static List<ApiEnvironmentProfile> _mergeEnvironments(
    List<ApiEnvironmentProfile> current,
    List<ApiEnvironmentProfile> imported,
  ) {
    final result = <String, ApiEnvironmentProfile>{};
    for (final value in [...current, ...imported]) {
      result[value.id] = value;
    }
    return result.values.toList();
  }
}
