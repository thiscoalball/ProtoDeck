import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/iperf_command_service.dart';

void main() {
  final service = IperfCommandService();

  test('accepts common client and server commands', () {
    final client = service.validate(
      'iperf3 -c 192.168.1.1 -t 10 -P 4',
      IperfMode.client,
    );
    expect(client.isValid, isTrue);
    expect(client.arguments, containsAllInOrder(['--connect-timeout', '5000']));
    expect(service.validate('iperf3 -s -1', IperfMode.server).isValid, isTrue);
  });

  test('keeps an explicit valid client connect timeout', () {
    final result = service.validate(
      'iperf3 -c 192.168.1.1 --connect-timeout 2500',
      IperfMode.client,
    );
    expect(result.isValid, isTrue);
    expect(
      result.arguments.where((value) => value == '--connect-timeout').length,
      1,
    );
    expect(
      service.clientExecutionTimeout(result.arguments),
      const Duration(milliseconds: 27500),
    );
  });

  test('rejects shell syntax and mode conflicts', () {
    expect(
      service.validate('iperf3 -c 1.2.3.4; reboot', IperfMode.client).isValid,
      isFalse,
    );
    expect(service.validate('iperf3 -s', IperfMode.client).isValid, isFalse);
    expect(
      service.validate('curl example.com', IperfMode.client).isValid,
      isFalse,
    );
  });

  test('enforces safe numeric limits', () {
    expect(
      service.validate('iperf3 -c 1.2.3.4 -p 70000', IperfMode.client).isValid,
      isFalse,
    );
    expect(
      service.validate('iperf3 -c 1.2.3.4 -P 100', IperfMode.client).isValid,
      isFalse,
    );
    expect(
      service
          .validate('iperf3 -c 1.2.3.4 --connect-timeout 10', IperfMode.client)
          .isValid,
      isFalse,
    );
  });
}
