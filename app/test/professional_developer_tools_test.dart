import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/data/app_database.dart';
import 'package:nettools_mobile/services/backend_engineering_service.dart';
import 'package:nettools_mobile/services/cron_workbench_service.dart';
import 'package:nettools_mobile/services/jwt_workbench_service.dart';
import 'package:nettools_mobile/services/regex_workbench_service.dart';
import 'package:nettools_mobile/services/structured_data_workbench_service.dart';
import 'package:nettools_mobile/services/tool_draft_repository.dart';
import 'package:nettools_mobile/services/timestamp_workbench_service.dart';
import 'package:nettools_mobile/state/app_state.dart';
import 'package:nettools_mobile/ui/pages/tools/structured_data_workbench_page.dart';

void main() {
  group('timestamp workbench', () {
    final service = TimestampWorkbenchService();

    test('recognizes seconds and renders selected IANA zones', () {
      final result = service.inspect(
        '0',
        outputZones: const ['Etc/UTC', 'Asia/Shanghai'],
      );
      expect(result.instant, DateTime.utc(1970));
      expect(result.zones, hasLength(2));
      expect(result.values.any((value) => value.value == '0'), isTrue);
    });

    test('interprets local input with an explicit IANA zone', () {
      final result = service.inspect(
        '2026-07-28 08:00:00',
        inputZone: 'Asia/Shanghai',
        outputZones: const ['Etc/UTC'],
      );
      expect(result.instant, DateTime.utc(2026, 7, 28));
    });

    test('limits unsafe batches', () {
      expect(
        () => service.inspectBatch(List.filled(501, '0').join('\n')),
        throwsFormatException,
      );
    });
  });

  group('regex workbench', () {
    final service = RegexWorkbenchService();

    test('returns groups and replacement preview', () {
      final result = service.analyze(
        pattern: r'user=(\w+)',
        input: 'user=alice user=bob',
        replacement: r'account=$1',
      );
      expect(result.matches, hasLength(2));
      expect(result.matches.first.groups.single, 'alice');
      expect(result.replaced, 'account=alice account=bob');
    });

    test('warns about nested quantifiers', () {
      expect(service.lint(r'(a+)+$', 'aaaa!'), isNotEmpty);
    });

    test('all presets compile in Dart', () {
      for (final preset in RegexWorkbenchService.presets) {
        expect(
          () => RegExp(preset.pattern),
          returnsNormally,
          reason: preset.name,
        );
      }
    });
  });

  group('structured data workbench', () {
    final service = StructuredDataWorkbenchService();

    test('sorts JSON keys recursively', () {
      expect(
        service.formatJson('{"z":{"b":1,"a":2},"a":0}', sortKeys: true),
        '{\n  "a": 0,\n  "z": {\n    "a": 2,\n    "b": 1\n  }\n}',
      );
    });

    test('compares arrays and nested objects semantically', () {
      final changes = service.compare(
        '{"items":[{"id":1,"state":"new"}]}',
        '{"items":[{"id":1,"state":"done"},{"id":2}]}',
      );
      expect(changes.map((value) => value.path), contains(r'$.items[0].state'));
      expect(changes.map((value) => value.path), contains(r'$.items[1]'));
    });

    test('validates required fields and simple constraints', () {
      final issues = service.validateSchema(
        '{"name":"x"}',
        '{"type":"object","required":["id"],"properties":{"name":{"type":"string","minLength":2}}}',
      );
      expect(issues, hasLength(2));
    });

    testWidgets('renders on a phone viewport and groups operations', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: StructuredDataWorkbenchPage()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('structured-data-mobile-scroll')), findsOne);
      expect(find.text('处理'), findsOneWidget);
      expect(find.text('校验'), findsOneWidget);
      expect(find.text('生成'), findsOneWidget);
      expect(find.text('格式化'), findsOneWidget);
      expect(find.text('JSONPath'), findsNothing);
      expect(find.text('格式转换'), findsNothing);
      expect(find.text('语义对比'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('structured-data-mode-select-process')),
      );
      await tester.pumpAndSettle();
      expect(find.text('JSONPath'), findsAtLeastNWidgets(1));
      expect(find.text('格式转换'), findsOneWidget);
      await tester.tap(find.text('JSONPath'));
      await tester.pumpAndSettle();
      expect(find.text('JSONPath'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('校验'));
      await tester.pumpAndSettle();

      expect(find.text('语义对比'), findsOneWidget);
      expect(find.text('Schema'), findsNothing);
      expect(find.text('格式化'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();

      expect(find.text('代码模型'), findsOneWidget);
      expect(find.text('Schema'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('restores a draft and safely switches dropdown-backed modes', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final database = AppDatabase(NativeDatabase.memory());
      final state = AppState(database: database);
      addTearDown(state.dispose);
      final drafts = ToolDraftRepository(database);
      await drafts.save('tool.structured_data', {
        'mode': 'convert',
        'source': '{"service":"ProtoDeck"}',
        'secondary': '',
        'argument': 'json_yaml',
        'sortKeys': false,
        'compact': false,
      });
      drafts.dispose();

      await tester.pumpWidget(
        MaterialApp(home: StructuredDataWorkbenchPage(appState: state)),
      );
      await tester.pumpAndSettle();

      expect(find.text('格式转换'), findsOneWidget);
      expect(find.textContaining('service: ProtoDeck'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();

      expect(find.text('代码模型'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('处理'));
      await tester.pumpAndSettle();

      expect(find.text('格式化'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('backend engineering workbench', () {
    final service = BackendEngineeringService();

    test('escapes SQL values and identifiers', () {
      final sql = service.jsonToInsert(
        '[{"id":1,"name":"O\'Reilly"}]',
        'public.users',
      );
      expect(sql, contains('INSERT INTO "public"."users"'));
      expect(sql, contains("'O''Reilly'"));
    });

    test('inspects UUID v7 timestamp', () {
      final result = service.inspectIdentifier(
        '0192f0bd-5f7a-7b42-8128-93f42028e624',
      );
      expect(result.kind, 'UUID');
      expect(result.fields['版本'], 'UUID v7');
      expect(result.fields['生成时间'], isNotNull);
    });

    test('implements SemVer prerelease precedence', () {
      expect(
        service.compareSemVer('1.0.0-alpha.2', '1.0.0-alpha.10'),
        lessThan(0),
      );
      expect(service.compareSemVer('1.0.0', '1.0.0-rc.1'), greaterThan(0));
      expect(service.compareSemVer('v2.1.0+build.5', '2.1.0+build.9'), 0);
    });

    test('detects invalid credentialed wildcard CORS', () {
      final result = service.inspectHttpHeaders(
        'Access-Control-Allow-Origin: *\nAccess-Control-Allow-Credentials: true',
      );
      expect(result.findings.any((item) => item.contains('CORS')), isTrue);
    });

    test('extracts levels and trace IDs from mixed logs', () {
      final result = service.inspectLogs(
        '{"level":"info","traceId":"abcdef0123456789"}\nERROR trace_id=abcdef0123456789 failed',
      );
      expect(result.total, 2);
      expect(result.levels['INFO'], 1);
      expect(result.levels['ERROR'], 1);
      expect(result.traceIds, ['abcdef0123456789']);
    });
  });

  group('JWT workbench', () {
    final service = JwtWorkbenchService();

    test('signs and verifies HMAC tokens', () {
      final token = service.sign(
        headerSource: '{"typ":"JWT"}',
        payloadSource: '{"sub":"user-1","exp":4102444800}',
        algorithm: 'HS256',
        secret: 'test-secret',
      );
      final result = service.inspect(token, secret: 'test-secret');
      expect(result.algorithm, 'HS256');
      expect(result.signatureStatus, 'VALID');
      expect(result.payload['sub'], 'user-1');
    });

    test('reports invalid secrets and missing expiry', () {
      final token = service.sign(
        headerSource: '{}',
        payloadSource: '{"sub":"user-1"}',
        algorithm: 'HS512',
        secret: 'right',
      );
      final result = service.inspect(token, secret: 'wrong');
      expect(result.signatureStatus, 'INVALID');
      expect(result.warnings.any((value) => value.contains('exp')), isTrue);
    });
  });

  group('Cron workbench', () {
    final service = CronWorkbenchService();

    test('explains fields and calculates requested runs', () {
      final result = service.inspect('*/15 9-18 * * 1-5', count: 5);
      expect(result.nextRuns, hasLength(5));
      expect(result.fields['分钟'], contains('15'));
      expect(result.expression, '*/15 9-18 * * 1-5');
    });

    test('expands common macros', () {
      expect(service.inspect('@daily', count: 1).expression, '0 0 * * *');
    });
  });
}
