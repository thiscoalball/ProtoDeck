import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/app.dart';
import 'package:nettools_mobile/data/app_database.dart';
import 'package:nettools_mobile/l10n/app_language.dart';
import 'package:nettools_mobile/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows main navigation and quick tools', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'app_language': 'zh_CN'});
    final state = AppState(database: AppDatabase(NativeDatabase.memory()));
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(NetToolsApp(state: state));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ProtoDeck'), findsOneWidget);
    expect(find.text('一键诊断'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('Wi‑Fi'), findsWidgets);
    expect(find.text('工具'), findsOneWidget);
    expect(find.text('远程'), findsOneWidget);
    expect(find.text('记录'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.byKey(const ValueKey('compact-signal-icon')), findsOneWidget);
    expect(find.text('信号强度'), findsWidgets);
    expect(find.text('核心信号'), findsNothing);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.theme?.textTheme.bodyMedium?.fontFamilyFallback,
      contains('NetToolsCJK'),
    );

    await state.setLanguage(AppLanguage.english);
    await tester.pump();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Run diagnosis'), findsOneWidget);
  });
}
