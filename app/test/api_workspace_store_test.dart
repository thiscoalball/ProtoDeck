import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/api_workspace_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'exports portable workspace without sent history or secret values',
    () async {
      final store = ApiWorkspaceStore();
      await store.saveList(ApiWorkspaceStore.templatesKey('rest'), [
        {
          'id': 'request-1',
          'name': 'Health',
          'method': 'GET',
          'url': 'https://example.test/health',
        },
      ]);
      await store.saveList(ApiWorkspaceStore.sentHistoryKey('websocket'), [
        {'payload': 'must-not-export'},
      ]);

      final bundle = await store.exportWorkspace();
      expect(bundle['format'], 'protodeck-api-workspace');
      final collections = bundle['collections'] as Map<String, Object?>;
      expect((collections['rest'] as List).single, contains('id'));
      expect(bundle.toString(), isNot(contains('must-not-export')));
    },
  );

  test(
    'merge import updates matching ids and preserves other requests',
    () async {
      final store = ApiWorkspaceStore();
      await store.saveList(ApiWorkspaceStore.templatesKey('rest'), [
        {'id': 'keep', 'name': 'Keep'},
        {'id': 'replace', 'name': 'Old'},
      ]);
      await store.importWorkspace({
        'format': 'protodeck-api-workspace',
        'schemaVersion': 1,
        'collections': {
          'rest': [
            {'id': 'replace', 'name': 'New'},
            {'id': 'added', 'name': 'Added'},
          ],
        },
        'messageTemplates': <String, Object?>{},
        'environments': <Object?>[],
      }, replace: false);

      final requests = await store.loadList(
        ApiWorkspaceStore.templatesKey('rest'),
      );
      expect(
        requests.map((item) => item['id']),
        containsAll(['keep', 'replace', 'added']),
      );
      expect(
        requests.singleWhere((item) => item['id'] == 'replace')['name'],
        'New',
      );
    },
  );

  test('rejects unknown workspace formats', () async {
    final store = ApiWorkspaceStore();
    expect(
      () => store.importWorkspace({'format': 'unknown'}, replace: true),
      throwsFormatException,
    );
  });
}
