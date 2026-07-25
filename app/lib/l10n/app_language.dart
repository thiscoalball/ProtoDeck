import 'package:flutter/widgets.dart';

enum AppLanguage {
  system,
  simplifiedChinese,
  english;

  Locale? get locale => switch (this) {
    AppLanguage.system => null,
    AppLanguage.simplifiedChinese => const Locale('zh', 'CN'),
    AppLanguage.english => const Locale('en', 'US'),
  };

  static AppLanguage fromStorage(String? value) => switch (value) {
    'zh_CN' => AppLanguage.simplifiedChinese,
    'en_US' => AppLanguage.english,
    _ => AppLanguage.system,
  };

  String get storageValue => switch (this) {
    AppLanguage.system => 'system',
    AppLanguage.simplifiedChinese => 'zh_CN',
    AppLanguage.english => 'en_US',
  };
}
