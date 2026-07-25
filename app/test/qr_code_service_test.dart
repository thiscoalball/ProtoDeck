import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/qr_code_service.dart';

void main() {
  final service = QrCodeService();

  test('builds standard URL, Wi-Fi, mail, phone and SMS payloads', () {
    expect(
      service.urlContent('https://example.com/a'),
      'https://example.com/a',
    );
    expect(
      service.wifiContent(
        ssid: 'Lab;5G',
        password: r'p:a\ss',
        encryption: 'WPA',
      ),
      r'WIFI:T:WPA;S:Lab\;5G;P:p\:a\\ss;H:false;;',
    );
    expect(
      service.emailContent(address: 'ops@example.com', subject: 'Alarm'),
      contains('mailto:ops@example.com'),
    );
    expect(service.phoneContent('+8613800138000'), 'tel:+8613800138000');
    expect(
      service.smsContent(number: '13800138000', message: '端口: down'),
      r'SMSTO:13800138000:端口\: down',
    );
  });

  test('creates a scannable matrix and deterministic SVG document', () {
    final matrix = service.create('https://example.com');
    expect(matrix.image.moduleCount, greaterThanOrEqualTo(21));
    expect(matrix.image.isDark(0, 0), isTrue);
    final svg = utf8.decode(
      service.renderSvg(
        matrix,
        size: 512,
        foregroundArgb: 0xff102a43,
        backgroundArgb: 0xffffffff,
      ),
    );
    expect(svg, contains('<svg'));
    expect(svg, contains('width="512"'));
    expect(svg, contains('fill="#102A43"'));
    expect(svg, contains('<path d="M'));
  });

  test('exports a valid PNG byte stream', () async {
    final matrix = service.create('WIFI:T:nopass;S:NetTools;P:;H:false;;');
    final png = await service.renderPng(
      matrix,
      size: 256,
      foregroundArgb: 0xff000000,
      backgroundArgb: 0xffffffff,
    );
    expect(png.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(png.length, greaterThan(500));
  });

  test('validates colors and structured content', () {
    expect(service.parseColor('#abc'), 0xffaabbcc);
    expect(() => service.parseColor('#12zz00'), throwsFormatException);
    expect(() => service.urlContent('example.com'), throwsFormatException);
    expect(
      () => service.wifiContent(ssid: 'Lab', password: '', encryption: 'WPA'),
      throwsFormatException,
    );
  });
}
