import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/ui/pages/tools/api_workbench_page.dart';
import 'package:nettools_mobile/ui/pages/tools/api_rest_workbench.dart';
import 'package:nettools_mobile/ui/pages/tools/developer_tool_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('API workbench exposes complete protocol workspaces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: ApiWorkbenchPage()));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'REST layout');
    expect(find.text('Params 2'), findsOneWidget);
    expect(find.textContaining('Headers'), findsWidgets);
    expect(find.text('Auth'), findsOneWidget);
    expect(find.textContaining('Body'), findsWidgets);
    expect(find.textContaining('Cookies'), findsWidgets);

    await tester.tap(find.text('WS'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'WebSocket layout');
    expect(find.text('WebSocket 调试'), findsOneWidget);
    expect(find.text('订阅消息模板'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);

    await tester.tap(find.text('SSE'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'SSE layout');
    expect(find.text('SSE 流调试'), findsOneWidget);
    expect(find.text('内容合并规则'), findsOneWidget);
    expect(find.textContaining('JSON 数组'), findsOneWidget);

    await tester.tap(find.text('MQTT'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'MQTT layout');
    expect(find.text('MQTT 调试'), findsOneWidget);
    expect(find.text('订阅列表'), findsOneWidget);
    expect(find.text('添加订阅'), findsOneWidget);
    expect(find.text('发布 Topic'), findsOneWidget);
  });

  testWidgets('Hash computes all digests in one action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeveloperToolPage(mode: 'hash')),
    );
    await tester.enterText(find.widgetWithText(TextField, '输入'), 'abc');
    await tester.tap(find.text('计算文本'));
    await tester.pump();
    expect(find.textContaining('MD5'), findsOneWidget);
    expect(find.textContaining('SHA-1'), findsOneWidget);
    expect(find.textContaining('SHA-224'), findsOneWidget);
    expect(find.textContaining('SHA-256'), findsOneWidget);
    expect(find.textContaining('SHA-384'), findsOneWidget);
    expect(find.textContaining('SHA-512'), findsOneWidget);
    expect(find.textContaining('CRC32'), findsOneWidget);
  });

  testWidgets(
    'saved REST cases retain their request and reopen from collection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: ApiWorkbenchPage()));
      await tester.pumpAndSettle();

      final urlField = find.byType(TextField).first;
      await tester.enterText(urlField, 'https://api.example.test/users/42');
      await tester.tap(find.text('保存用例'));
      await tester.pumpAndSettle();

      final nameField = find.ancestor(
        of: find.text('用例名称'),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'Load user');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('api_workspace_templates_v1_rest'),
        contains('Load user'),
      );

      await tester.tap(find.byTooltip('请求集合'));
      await tester.pumpAndSettle();
      expect(find.text('Load user'), findsOneWidget);
      expect(find.text('https://api.example.test/users/42'), findsWidgets);

      await tester.tap(find.text('Load user'));
      await tester.pumpAndSettle();
      expect(find.text('API 调试台'), findsOneWidget);
      expect(
        tester
            .widget<ApiRestWorkbench>(find.byType(ApiRestWorkbench))
            .initialTemplateId,
        isNotNull,
      );
      final reopenedUrl = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(reopenedUrl.controller?.text, 'https://api.example.test/users/42');
    },
  );
}
