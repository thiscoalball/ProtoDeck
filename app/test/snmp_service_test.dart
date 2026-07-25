import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/snmp_service.dart';

void main() {
  test('SNMPv3 rejects missing username before network access', () async {
    expect(
      () => SnmpService().requestV3(
        host: '127.0.0.1',
        credentials: const SnmpV3Credentials(
          username: '',
          securityLevel: SnmpV3SecurityLevel.noAuthNoPriv,
        ),
        oids: const ['1.3.6.1.2.1.1.1.0'],
      ),
      throwsFormatException,
    );
  });

  test(
    'SNMPv3 validates authentication and privacy password lengths',
    () async {
      final service = SnmpService();
      expect(
        () => service.requestV3(
          host: '127.0.0.1',
          credentials: const SnmpV3Credentials(
            username: 'tester',
            securityLevel: SnmpV3SecurityLevel.authNoPriv,
            authPassword: 'short',
          ),
          oids: const ['1.3.6.1.2.1.1.1.0'],
        ),
        throwsFormatException,
      );
      expect(
        () => service
            .walkV3(
              host: '127.0.0.1',
              credentials: const SnmpV3Credentials(
                username: 'tester',
                securityLevel: SnmpV3SecurityLevel.authPriv,
                authPassword: 'long-enough',
                privacyPassword: 'short',
              ),
              rootOid: '1.3.6.1.2.1.1',
            )
            .drain<void>(),
        throwsFormatException,
      );
    },
  );
}
