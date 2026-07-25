import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/data/app_database.dart';
import 'package:nettools_mobile/l10n/app_localizations.dart';
import 'package:nettools_mobile/state/app_state.dart';
import 'package:nettools_mobile/ui/tool_catalog.dart';
import 'package:nettools_mobile/ui/tool_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('every tool initial surface is English in English mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'app_language': 'en_US'});
    final state = AppState(database: AppDatabase(NativeDatabase.memory()));
    await state.initialize();
    addTearDown(state.dispose);

    final han = RegExp(r'[\u3400-\u9fff]');
    final untranslated = <String, Set<String>>{};

    for (final tool in toolCatalog) {
      final page = buildToolPage(tool.id, state);
      expect(page, isNotNull, reason: 'No page for ${tool.id}');
      await tester.pumpWidget(_EnglishTestApp(home: page!));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      for (final value in _visibleStrings(tester)) {
        if (han.hasMatch(value)) {
          untranslated.putIfAbsent(value, () => <String>{}).add(tool.id);
        }
      }

      // This audit owns localization only. Individual pages have dedicated
      // behavior/layout tests, so drain unrelated platform and overflow
      // exceptions without turning them into false localization failures.
      while (tester.takeException() != null) {}

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    expect(
      untranslated,
      isEmpty,
      reason:
          'Visible Chinese in English tool pages (${untranslated.length}): '
          '${untranslated.entries.map((entry) => '${entry.key} @ ${entry.value.join(', ')}').join('\n')}',
    );
  });
}

Iterable<String> _visibleStrings(WidgetTester tester) sync* {
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final value = widget.data ?? widget.textSpan?.toPlainText();
    if (value != null && value.trim().isNotEmpty) yield value;
  }
  for (final element in find.byType(SelectableText).evaluate()) {
    final widget = element.widget as SelectableText;
    final value = widget.data ?? widget.textSpan?.toPlainText();
    if (value != null && value.trim().isNotEmpty) yield value;
  }
  for (final element in find.byType(EditableText).evaluate()) {
    final widget = element.widget as EditableText;
    final value = widget.controller.text;
    if (value.trim().isNotEmpty) yield value;
  }
  for (final element in find.byType(Tooltip).evaluate()) {
    final widget = element.widget as Tooltip;
    final value = widget.message ?? widget.richMessage?.toPlainText();
    if (value != null && value.trim().isNotEmpty) yield value;
  }
}

class _EnglishTestApp extends StatelessWidget {
  const _EnglishTestApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('en', 'US'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}
