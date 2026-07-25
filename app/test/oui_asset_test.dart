import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/core/oui/oui_repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('bundled IEEE OUI database is complete and queryable offline', () {
    final file = File('assets/data/ieee_oui.db');
    expect(file.existsSync(), isTrue);
    final database = sqlite3.open(file.path, mode: OpenMode.readOnly);
    addTearDown(database.close);
    expect(database.select('PRAGMA integrity_check').first.values.first, 'ok');
    final counts = database.select(
      'SELECT registry, COUNT(*) count FROM oui_prefix GROUP BY registry',
    );
    final byRegistry = {
      for (final row in counts) row['registry']: row['count'],
    };
    expect(byRegistry['MA-L'], greaterThanOrEqualTo(39000));
    expect(byRegistry['MA-M'], greaterThanOrEqualTo(6400));
    expect(byRegistry['MA-S'], greaterThanOrEqualTo(7000));
    final sample = database.select(
      'SELECT organization_name FROM oui_prefix WHERE prefix_length = 24 AND prefix_value = ?',
      [0x00000C],
    );
    expect(sample, isNotEmpty);
  });

  test('organization reverse lookup source data is searchable', () {
    final database = sqlite3.open(
      'assets/data/ieee_oui.db',
      mode: OpenMode.readOnly,
    );
    addTearDown(database.close);
    final rows = database.select(
      '''
      SELECT assignment, prefix_length, prefix_value, organization_name,
             CASE
               WHEN organization_name = ? COLLATE NOCASE THEN 0
               WHEN organization_name LIKE ? ESCAPE '\\' COLLATE NOCASE THEN 1
               ELSE 2
             END AS match_rank
      FROM oui_prefix
      WHERE organization_name LIKE ? ESCAPE '\\' COLLATE NOCASE
      ORDER BY match_rank, organization_name COLLATE NOCASE,
               prefix_length DESC, assignment
      LIMIT 20
      ''',
      ['Cisco', 'Cisco%', '%Cisco%'],
    );
    expect(rows, isNotEmpty);
    expect(
      rows.any(
        (row) => (row['organization_name'] as String).toLowerCase().contains(
          'cisco',
        ),
      ),
      isTrue,
    );
  });

  test('formats MA-L, MA-M and MA-S allocation ranges', () {
    const maL = OuiOrganizationPrefix(
      registry: 'MA-L',
      assignment: '00000C',
      prefixLength: 24,
      prefixValue: 0x00000C,
      organizationName: 'Cisco Systems, Inc',
      organizationAddress: '',
    );
    expect(maL.formattedPrefix, '00:00:0C:00:00:00/24');
    expect(maL.lastAddress, '00:00:0C:FF:FF:FF');

    const maM = OuiOrganizationPrefix(
      registry: 'MA-M',
      assignment: 'AABBCCD',
      prefixLength: 28,
      prefixValue: 0xAABBCCD,
      organizationName: 'Example',
      organizationAddress: '',
    );
    expect(maM.firstAddress, 'AA:BB:CC:D0:00:00');
    expect(maM.lastAddress, 'AA:BB:CC:DF:FF:FF');

    const maS = OuiOrganizationPrefix(
      registry: 'MA-S',
      assignment: 'AABBCCDDE',
      prefixLength: 36,
      prefixValue: 0xAABBCCDDE,
      organizationName: 'Example',
      organizationAddress: '',
    );
    expect(maS.firstAddress, 'AA:BB:CC:DD:E0:00');
    expect(maS.lastAddress, 'AA:BB:CC:DD:EF:FF');
  });
}
