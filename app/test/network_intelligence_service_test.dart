import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/network_intelligence_service.dart';

void main() {
  test('does not send private addresses to public RDAP providers', () async {
    await expectLater(
      IpOwnershipService().lookup('192.168.1.1'),
      throwsA(isA<FormatException>()),
    );
  });
}
