import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/wildcard_mask_service.dart';

void main() {
  final service = WildcardMaskService();

  test('converts subnet mask, wildcard mask and CIDR consistently', () {
    final fromSubnet = service.calculate(
      '255.255.255.0',
      WildcardInputType.subnetMask,
    );
    final fromWildcard = service.calculate(
      '0.0.0.255',
      WildcardInputType.wildcardMask,
    );
    final fromCidr = service.calculate('/24', WildcardInputType.cidr);
    for (final result in [fromSubnet, fromWildcard, fromCidr]) {
      expect(result.prefix, 24);
      expect(result.subnetMask, '255.255.255.0');
      expect(result.wildcardMask, '0.0.0.255');
      expect(result.subnetBinary, '11111111.11111111.11111111.00000000');
      expect(result.wildcardBinary, '00000000.00000000.00000000.11111111');
    }
  });

  test('handles /0 and /32 boundaries', () {
    expect(
      service.calculate('0', WildcardInputType.cidr).wildcardMask,
      '255.255.255.255',
    );
    expect(
      service.calculate('32', WildcardInputType.cidr).wildcardMask,
      '0.0.0.0',
    );
  });

  test('rejects non-contiguous masks and wildcards', () {
    expect(
      () => service.calculate('255.0.255.0', WildcardInputType.subnetMask),
      throwsFormatException,
    );
    expect(
      () => service.calculate('0.255.0.255', WildcardInputType.wildcardMask),
      throwsFormatException,
    );
  });

  test('derives the matched ACL address range', () {
    final mask = service.calculate('24', WildcardInputType.cidr);
    final range = service.matchRange('192.168.7.82', mask);
    expect(range.networkAddress, '192.168.7.0');
    expect(range.lastAddress, '192.168.7.255');
    expect(range.aclAddressWildcard, '192.168.7.0 0.0.0.255');
  });
}
