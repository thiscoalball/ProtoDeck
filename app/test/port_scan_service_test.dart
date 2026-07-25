import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/port_scan_service.dart';

void main() {
  final service = PortScanService();

  test('parses individual ports and ranges', () {
    expect(service.parsePorts('443,80,8000-8002'), [80, 443, 8000, 8001, 8002]);
  });

  test('rejects invalid and excessive ranges', () {
    expect(() => service.parsePorts('0'), throwsFormatException);
    expect(() => service.parsePorts('1-300'), throwsFormatException);
    expect(() => service.parsePorts('abc'), throwsFormatException);
  });
}
