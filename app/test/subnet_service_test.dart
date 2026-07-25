import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/subnet_service.dart';

void main() {
  final service = SubnetService();

  test('calculates an IPv4 /24 network', () {
    final result = service.calculate('192.168.1.10/24');
    expect(result.network, '192.168.1.0/24');
    expect(result.broadcast, '192.168.1.255');
    expect(result.mask, '255.255.255.0');
    expect(result.firstHost, '192.168.1.1');
    expect(result.lastHost, '192.168.1.254');
    expect(result.usableHosts, 254);
  });

  test('rejects invalid IPv4 input', () {
    expect(() => service.calculate('192.168.1.999/24'), throwsFormatException);
    expect(() => service.calculate('192.168.1.1/33'), throwsFormatException);
  });

  test('calculates IPv6 boundaries and /64 network count', () {
    final result = service.calculateIpv6('2001:db8:1234:5678::42/48');
    expect(result.network, '2001:db8:1234::/48');
    expect(result.firstAddress, '2001:db8:1234::');
    expect(result.lastAddress, '2001:db8:1234:ffff:ffff:ffff:ffff:ffff');
    expect(result.totalAddresses, BigInt.one << 80);
    expect(result.slash64Networks, BigInt.from(65536));
  });

  test(
    'handles IPv6 /128 and formats large counts without exponent notation',
    () {
      final result = service.calculateIpv6('2001:db8::1/128');
      expect(result.network, '2001:db8::1/128');
      expect(result.lastAddress, '2001:db8::1');
      expect(result.totalAddresses, BigInt.one);
      expect(result.slash64Networks, isNull);
      expect(
        service.formatCount(
          BigInt.parse('340282366920938463463374607431768211456'),
        ),
        '340,282,366,920,938,463,463,374,607,431,768,211,456',
      );
    },
  );

  test('rejects invalid IPv6 prefixes', () {
    expect(
      () => service.calculateIpv6('2001:db8::/129'),
      throwsFormatException,
    );
    expect(
      () => service.calculateIpv6('192.168.1.1/64'),
      throwsFormatException,
    );
  });
}
