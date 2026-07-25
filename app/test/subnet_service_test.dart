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
}
