import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/network_intelligence_service.dart';

void main() {
  test('TLS inspection result exposes validity and address metadata', () {
    final now = DateTime.now();
    final result = TlsInspectionResult(
      host: 'example.test',
      address: '2001:db8::1',
      resolvedAddresses: const ['2001:db8::1', '192.0.2.1'],
      port: 443,
      dnsTime: const Duration(milliseconds: 2),
      connectTime: const Duration(milliseconds: 3),
      handshakeTime: const Duration(milliseconds: 4),
      totalTime: const Duration(milliseconds: 9),
      trusted: false,
      selectedProtocol: 'h2',
      requestedProtocols: const ['h2', 'http/1.1'],
      subject: 'CN=example.test',
      issuer: 'CN=example.test',
      validFrom: now.subtract(const Duration(days: 1)),
      validTo: now.add(const Duration(days: 30)),
      sha1Fingerprint: 'AA',
      sha256Fingerprint: 'BB',
      derLength: 123,
      certificatePem: 'PEM',
    );

    expect(result.addressType, InternetAddressType.IPv6);
    expect(result.selfIssued, isTrue);
    expect(result.expired, isFalse);
    expect(result.notYetValid, isFalse);
    expect(result.trusted, isFalse);
  });

  test('does not send private addresses to public RDAP providers', () async {
    await expectLater(
      IpOwnershipService().lookup('192.168.1.1'),
      throwsA(isA<FormatException>()),
    );
  });
}
