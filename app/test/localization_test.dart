import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/l10n/app_language.dart';
import 'package:nettools_mobile/l10n/app_localizations.dart';
import 'package:nettools_mobile/l10n/strings/tool_page_strings.dart';
import 'package:nettools_mobile/ui/tool_catalog.dart';

void main() {
  test('supported language values round-trip through storage', () {
    for (final language in AppLanguage.values) {
      expect(AppLanguage.fromStorage(language.storageValue), language);
    }
    expect(AppLanguage.fromStorage(null), AppLanguage.system);
  });

  test('localization modules resolve Chinese and English independently', () {
    final zh = AppLocalizations(const Locale('zh', 'CN'));
    final en = AppLocalizations(const Locale('en', 'US'));

    expect(zh.navigation.home, '首页');
    expect(en.navigation.home, 'Home');
    expect(zh.settings.pageTitle, '设置');
    expect(en.settings.pageTitle, 'Settings');
    expect(en.dashboard.connectionNormal, 'Connected');
  });

  test('every catalog entry has English discovery copy', () {
    final strings = AppLocalizations(const Locale('en', 'US')).tools;
    final han = RegExp(r'[\u3400-\u9fff]');

    for (final tool in toolCatalog) {
      final copy = strings.resolve(
        id: tool.id,
        fallbackName: tool.name,
        fallbackDescription: tool.description,
      );
      expect(copy.name, isNotEmpty, reason: tool.id);
      expect(copy.description, isNotEmpty, reason: tool.id);
      expect(han.hasMatch(copy.name), isFalse, reason: tool.id);
      expect(han.hasMatch(copy.description), isFalse, reason: tool.id);
    }
  });

  test('localized UI literals have an English rendering', () {
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final literals = [
      RegExp(r"LocalizedText\(\s*r?'([^']*[\u4e00-\u9fff][^']*)'"),
      RegExp(r"context\.tr\(\s*r?'([^']*[\u4e00-\u9fff][^']*)'"),
      RegExp(
        r"(?:_status|_error|_message|_result|_output)\s*=\s*r?'([^']*[\u4e00-\u9fff][^']*)'",
      ),
    ];
    final chinese = RegExp(r'[\u4e00-\u9fff]');
    const strings = ToolPageStrings(isEnglish: true);
    final missing = <String>{};
    for (final file in files) {
      final sourceCode = file.readAsStringSync();
      for (final literal in literals) {
        for (final match in literal.allMatches(sourceCode)) {
          final source = match.group(1)!;
          if (chinese.hasMatch(strings.translate(source))) missing.add(source);
        }
      }
    }
    expect(missing, isEmpty, reason: 'Missing UI translations: $missing');
  });

  test('Wi-Fi analyzer has no untranslated Chinese UI literals', () {
    final sourceCode = File(
      'lib/ui/pages/tools/wifi_analyzer_page.dart',
    ).readAsStringSync();
    final literals = RegExp(
      r"r?'([^'\n]*[\u4e00-\u9fff][^'\n]*)'",
    ).allMatches(sourceCode);
    final chinese = RegExp(r'[\u4e00-\u9fff]');
    const strings = ToolPageStrings(isEnglish: true);
    final missing = <String>{
      for (final match in literals)
        if (chinese.hasMatch(strings.translate(match.group(1)!)))
          match.group(1)!,
    };
    expect(missing, isEmpty, reason: 'Missing Wi-Fi translations: $missing');
  });

  test('UI string-only sinks do not bypass localization', () {
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final bypassPatterns = <RegExp>[
      RegExp(r"Tab\([^\n]*\btext:\s*'[^']*[\u4e00-\u9fff][^']*'"),
      RegExp(r"SelectableText\(\s*'[^']*[\u4e00-\u9fff][^']*'"),
      RegExp(r"TextEditingController\(\s*text:\s*'[^']*[\u4e00-\u9fff][^']*'"),
      RegExp(r"dialogTitle:\s*'[^']*[\u4e00-\u9fff][^']*'"),
      RegExp(r"TextSourceAttribution\(\s*'[^']*[\u4e00-\u9fff][^']*'"),
    ];
    final bypasses = <String>[];
    for (final file in files) {
      final sourceCode = file.readAsStringSync();
      for (final pattern in bypassPatterns) {
        for (final match in pattern.allMatches(sourceCode)) {
          bypasses.add('${file.path}: ${match.group(0)}');
        }
      }
    }
    expect(bypasses, isEmpty, reason: 'Localization bypasses: $bypasses');
  });
}
