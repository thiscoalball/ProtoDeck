import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/mac_format_service.dart';

void main() {
  final service = MacFormatService();

  test('accepts colon, hyphen, Cisco and plain MAC formats', () {
    for (final input in [
      'aa:bb:cc:dd:ee:ff',
      'AA-BB-CC-DD-EE-FF',
      'aabb.ccdd.eeff',
      'AABBCCDDEEFF',
    ]) {
      final result = service.format(input);
      expect(result.colon, 'aa:bb:cc:dd:ee:ff');
      expect(result.hyphen, 'aa-bb-cc-dd-ee-ff');
      expect(result.cisco, 'aabb.ccdd.eeff');
      expect(result.plain, 'aabbccddeeff');
    }
  });

  test('switches every output to uppercase', () {
    final result = service.format('aabb.ccdd.eeff', uppercase: true);
    expect(result.colon, 'AA:BB:CC:DD:EE:FF');
    expect(result.cisco, 'AABB.CCDD.EEFF');
  });

  test('rejects incomplete or invalid input', () {
    expect(() => service.format('aa:bb:cc'), throwsFormatException);
    expect(() => service.format('aa:bb:cc:dd:ee:gg'), throwsFormatException);
  });
}
