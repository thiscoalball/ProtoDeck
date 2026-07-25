import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final value = jsonDecode(encoded);
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList();
    } on Object {
      return const [];
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

  static String _secretKey(String scope) => 'api_workspace_secret_v1_$scope';
}
