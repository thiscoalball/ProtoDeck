import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';
import '../l10n/app_language.dart';
import '../models/tool_history.dart';

class AppState extends ChangeNotifier {
  static const _historyKey = 'tool_history_v1';
  static const _darkModeKey = 'dark_mode';
  static const _languageKey = 'app_language';

  AppState({AppDatabase? database})
    : database = database ?? AppDatabase.defaults();

  final AppDatabase database;
  final List<ToolHistoryEntry> _history = [];
  late SharedPreferences _preferences;
  ThemeMode _themeMode = ThemeMode.system;
  AppLanguage _language = AppLanguage.system;

  List<ToolHistoryEntry> get history => List.unmodifiable(_history);
  ThemeMode get themeMode => _themeMode;
  AppLanguage get language => _language;

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
    final storedTheme = _preferences.getString(_darkModeKey);
    _themeMode = switch (storedTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _language = AppLanguage.fromStorage(_preferences.getString(_languageKey));

    // Tool history is intentionally disabled. Existing rows are left untouched
    // so an upgrade never silently deletes user data, but the app neither
    // loads nor writes diagnostic inputs or results.
    _history.clear();
  }

  Future<void> addHistory({
    required String tool,
    required String title,
    required String summary,
    required String detail,
    required bool success,
  }) async {}

  Future<void> removeHistory(String id) async {
    await (database.delete(
      database.toolSessions,
    )..where((row) => row.id.equals(id))).go();
    await _reloadHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await database.delete(database.toolSessions).go();
    _history.clear();
    await _preferences.remove(_historyKey);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _preferences.setString(_darkModeKey, mode.name);
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    await _preferences.setString(_languageKey, language.storageValue);
    notifyListeners();
  }

  Future<void> _reloadHistory() async {
    final rows = await database.recentSessions();
    _history
      ..clear()
      ..addAll(
        rows.map(
          (row) => ToolHistoryEntry(
            id: row.id,
            tool: row.tool,
            title: row.title,
            summary: row.summary,
            detail: row.detail,
            timestamp: row.startedAt,
            success: row.success,
          ),
        ),
      );
  }

  @override
  void dispose() {
    database.close();
    super.dispose();
  }
}
