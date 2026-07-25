import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/ui/pages/tools/api_workbench_page.dart';
import 'package:nettools_mobile/ui/pages/tools/developer_tool_page.dart';

void main() {
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
    expect(find.textContaining('SHA-256'), findsOneWidget);
    expect(find.textContaining('SHA-512'), findsOneWidget);
    expect(find.textContaining('CRC32'), findsOneWidget);
  });
}
