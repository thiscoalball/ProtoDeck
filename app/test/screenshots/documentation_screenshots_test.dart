import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/app.dart';
import 'package:nettools_mobile/core/oui/oui_repository.dart';
import 'package:nettools_mobile/data/app_database.dart';
import 'package:nettools_mobile/state/app_state.dart';
import 'package:nettools_mobile/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phoneSize = Size(390, 844);
const _desktopSize = Size(1440, 900);
const _captureKey = ValueKey('documentation-capture');
const _screenshotLanguages = [
  (label: 'English', storageValue: 'en_US', suffix: ''),
  (label: 'Simplified Chinese', storageValue: 'zh_CN', suffix: '-zh'),
];

void main() {
  setUpAll(_loadScreenshotFonts);

  final routeCaptures =
      <({String description, String route, Size size, String fileName})>[
        (
          description: 'Android home',
          route: '/',
          size: _phoneSize,
          fileName: 'android-home.png',
        ),
        (
          description: 'Android Wi-Fi',
          route: '/wifi',
          size: _phoneSize,
          fileName: 'android-wifi.png',
        ),
        (
          description: 'Android tools',
          route: '/tools',
          size: _phoneSize,
          fileName: 'android-tools.png',
        ),
        (
          description: 'Android remote sessions',
          route: '/remote',
          size: _phoneSize,
          fileName: 'android-remote.png',
        ),
        (
          description: 'Android settings',
          route: '/settings',
          size: _phoneSize,
          fileName: 'android-settings.png',
        ),
        (
          description: 'desktop home layout',
          route: '/',
          size: _desktopSize,
          fileName: 'desktop-home.png',
        ),
        (
          description: 'desktop tools layout',
          route: '/tools',
          size: _desktopSize,
          fileName: 'desktop-tools.png',
        ),
        (
          description: 'desktop remote layout',
          route: '/remote',
          size: _desktopSize,
          fileName: 'desktop-remote.png',
        ),
      ];

  for (final language in _screenshotLanguages) {
    for (final capture in routeCaptures) {
      testWidgets(
        'generate ${language.label} ${capture.description} documentation screenshot',
        (tester) async {
          final state = await _pumpApp(
            tester,
            initialLocation: capture.route,
            surfaceSize: capture.size,
            language: language.storageValue,
          );
          await _capture(
            tester,
            _localizedFileName(capture.fileName, language.suffix),
          );
          await _disposeApp(tester, state);
        },
      );
    }
  }

  final toolCaptures =
      <
        ({
          String description,
          String englishToolName,
          String chineseToolName,
          Size size,
          String fileName,
        })
      >[
        (
          description: 'Android Ping',
          englishToolName: 'Ping',
          chineseToolName: 'Ping',
          size: _phoneSize,
          fileName: 'android-ping.png',
        ),
        (
          description: 'Android network doctor',
          englishToolName: 'Network Doctor',
          chineseToolName: '一键网络医生',
          size: _phoneSize,
          fileName: 'android-network-doctor.png',
        ),
        (
          description: 'Android JSON workbench',
          englishToolName: 'JSON & Data Workbench',
          chineseToolName: 'JSON 与数据工作台',
          size: _phoneSize,
          fileName: 'android-json-workbench.png',
        ),
        (
          description: 'Android API workbench',
          englishToolName: 'API Workbench',
          chineseToolName: 'API 调试台',
          size: _phoneSize,
          fileName: 'android-api-workbench.png',
        ),
        (
          description: 'desktop API workbench',
          englishToolName: 'API Workbench',
          chineseToolName: 'API 调试台',
          size: _desktopSize,
          fileName: 'desktop-api-workbench.png',
        ),
      ];

  for (final language in _screenshotLanguages) {
    for (final capture in toolCaptures) {
      testWidgets(
        'generate ${language.label} ${capture.description} documentation screenshot',
        (tester) async {
          final state = await _pumpApp(
            tester,
            initialLocation: '/tools',
            surfaceSize: capture.size,
            language: language.storageValue,
          );
          await _openTool(
            tester,
            language.storageValue == 'zh_CN'
                ? capture.chineseToolName
                : capture.englishToolName,
          );
          await _capture(
            tester,
            _localizedFileName(capture.fileName, language.suffix),
          );
          await _disposeApp(tester, state);
        },
      );
    }
  }
}

String _localizedFileName(String fileName, String suffix) =>
    fileName.replaceFirst('.png', '$suffix.png');

Future<AppState> _pumpApp(
  WidgetTester tester, {
  required String initialLocation,
  required Size surfaceSize,
  required String language,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

  SharedPreferences.setMockInitialValues({
    'app_language': language,
    'dark_mode': 'light',
  });
  final state = AppState(database: AppDatabase(NativeDatabase.memory()));
  await state.initialize();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => state),
        ouiRepositoryProvider.overrideWithValue(_ScreenshotOuiRepository()),
      ],
      child: RepaintBoundary(
        key: _captureKey,
        child: NetToolsApp(
          state: state,
          initialLocation: initialLocation,
          // Keep Latin glyphs in Roboto and let ThemeData fall back to the
          // bundled CJK font for Chinese. Using the CJK face as the sole
          // primary family would turn protocol labels such as REST into tofu.
          // Keep the documentation subset under a unique family name. The
          // production NetToolsCJK family is already registered from pubspec
          // and must not shadow the deterministic Simplified Chinese face.
          fontFamilyOverride: language == 'zh_CN'
              ? 'ProtoDeckDocsCJK'
              : 'Roboto',
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return state;
}

Future<void> _openTool(WidgetTester tester, String toolName) async {
  final search = find.byType(SearchBar);
  expect(search, findsOneWidget);
  await tester.enterText(search, toolName);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  final title = find.text(toolName);
  expect(title, findsWidgets);
  // The search field's EditableText also contains the query. The last match
  // is the title inside the filtered tool tile.
  await tester.tap(title.last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _loadScreenshotFonts() async {
  final documentationCjk = File('test/assets/ProtoDeckDocsCJKSubset.otf');
  if (!documentationCjk.existsSync()) {
    throw StateError(
      'Documentation CJK subset font not found: ${documentationCjk.path}',
    );
  }
  // flutter_tester does not reliably fall back between multiple files that
  // are registered under one family. The documentation subset contains both
  // Latin and every CJK glyph used by the UI, so each test family deliberately
  // receives exactly that one face.
  final latin = FontLoader('Roboto')..addFont(_readFont(documentationCjk));
  // Several Material controls intentionally supply their own text style and
  // flutter_tester resolves its unspecified family to Ahem. Re-registering
  // that test-only family with Roboto keeps every control human-readable.
  final testFallback = FontLoader('Ahem')..addFont(_readFont(documentationCjk));
  final monospaceFallback = FontLoader('monospace')
    ..addFont(_readFont(documentationCjk));
  final cjk = FontLoader('ProtoDeckDocsCJK')
    ..addFont(_readFont(documentationCjk));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await Future.wait([
    latin.load(),
    testFallback.load(),
    monospaceFallback.load(),
    cjk.load(),
    materialIcons.load(),
  ]);
}

Future<ByteData> _readFont(File file) async =>
    ByteData.sublistView(await file.readAsBytes());

Future<void> _disposeApp(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  state.dispose();
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _capture(WidgetTester tester, String fileName) async {
  // Let ink, route, and implicit animations reach a stable final frame.
  await tester.pump(const Duration(milliseconds: 500));
  await expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile('../../../docs/screenshots/$fileName'),
  );
}

class _ScreenshotOuiRepository extends OuiRepository {
  @override
  OuiDatabaseMetadata metadata() => OuiDatabaseMetadata(
    generatedAt: DateTime.utc(2026, 7, 1),
    counts: const {'MA-L': 39807, 'MA-M': 6498, 'MA-S': 7108},
    lastModified: const {},
    fileSize: 5 * 1024 * 1024,
  );
}
