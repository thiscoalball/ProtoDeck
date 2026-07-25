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

  test('derives address attributes and modified EUI-64', () {
    final globalUnicast = service.format('00:11:22:33:44:55');
    expect(globalUnicast.isMulticast, isFalse);
    expect(globalUnicast.isLocallyAdministered, isFalse);
    expect(globalUnicast.modifiedEui64, '0211:22ff:fe33:4455');
    expect(globalUnicast.linkLocalIpv6, 'fe80::0211:22ff:fe33:4455');

    final localMulticast = service.format('03:00:00:00:00:01');
    expect(localMulticast.isMulticast, isTrue);
    expect(localMulticast.isLocallyAdministered, isTrue);
  });

  test('rejects incomplete or invalid input', () {
    expect(() => service.format('aa:bb:cc'), throwsFormatException);
    expect(() => service.format('aa:bb:cc:dd:ee:gg'), throwsFormatException);
  });
}
