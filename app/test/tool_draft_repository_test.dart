import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/data/app_database.dart';
import 'package:nettools_mobile/services/tool_draft_repository.dart';

void main() {
  late AppDatabase database;
  late ToolDraftRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = ToolDraftRepository(database);
  });

  tearDown(() async {
    repository.dispose();
    await database.close();
  });

  test('restores safe page state across repository instances', () async {
    await repository.save('tool.ping', {
      'host': '192.168.8.1',
      'count': '10',
      'continuous': true,
    });

    final restored = await ToolDraftRepository(database).load('tool.ping');
    expect(restored?.payload['host'], '192.168.8.1');
    expect(restored?.payload['continuous'], isTrue);
  });

  test('strips credentials recursively before writing SQLite', () async {
    await repository.save('tool.api', {
      'url': 'https://example.test',
      'password': 'do-not-store',
      'headers': {
        'Accept': 'application/json',
        'Authorization': 'Bearer secret',
      },
      'nested': [
        {'apiKey': 'secret', 'visible': 'kept'},
        {'name': 'X-API-Key', 'value': 'also-secret', 'enabled': true},
        {'key': 'Cookie', 'content': 'session=secret'},
      ],
    });

    final restored = await repository.load('tool.api');
    expect(restored?.payload.containsKey('password'), isFalse);
    expect(
      (restored?.payload['headers'] as Map<Object?, Object?>).containsKey(
        'Authorization',
      ),
      isFalse,
    );
    expect(
      ((restored?.payload['nested'] as List<Object?>).first
              as Map<Object?, Object?>)['visible'],
      'kept',
    );
    final nested = restored?.payload['nested'] as List<Object?>;
    expect((nested[1] as Map<Object?, Object?>).containsKey('value'), isFalse);
    expect((nested[2] as Map<Object?, Object?>).containsKey('content'), isFalse);
  });

  test('drops incompatible draft schema instead of applying stale fields', () async {
    await repository.save(
      'tool.dns',
      {'host': 'example.com'},
      policy: const DraftPolicy(schemaVersion: 1),
    );

    final restored = await repository.load(
      'tool.dns',
      policy: const DraftPolicy(schemaVersion: 2),
    );
    expect(restored, isNull);
    expect(await database.getToolDraft('tool.dns'), isNull);
  });
}
