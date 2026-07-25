import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/data/app_database.dart';
import 'package:nettools_mobile/state/app_state.dart';
import 'package:nettools_mobile/ui/pages/tools/ping_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Ping keeps advanced controls collapsed and actions obvious', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final state = AppState(database: AppDatabase(NativeDatabase.memory()));
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PingPage(appState: state, initialHost: '192.168.8.1'),
      ),
    );
    await tester.pump();

    expect(find.text('测试目标'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '阿里 DNS'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '百度'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Cloudflare'), findsOneWidget);
    expect(find.text('持续 Ping'), findsNothing);
    expect(find.text('开始测试'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('测试参数'));
    await tester.pumpAndSettle();
    expect(find.text('持续 Ping'), findsOneWidget);
    expect(find.text('协议版本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
