import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:qr/qr.dart' as qr;

enum QrContentType { url, wifi, email, phone, sms }

class QrMatrix {
  const QrMatrix({required this.image, required this.content});

  final qr.QrImage image;
  final String content;
}

class QrCodeService {
  QrMatrix create(String content) {
    if (content.isEmpty) throw const FormatException('二维码内容不能为空');
    final code = qr.QrCode(
      payload: qr.QrPayload.fromString(content),
      errorCorrectLevel: qr.QrErrorCorrectLevel.medium,
    );
    return QrMatrix(image: qr.QrImage(code), content: content);
  }

  String urlContent(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('请输入完整的 http:// 或 https:// URL');
    }
    return uri.toString();
  }

  String wifiContent({
    required String ssid,
    required String password,
    required String encryption,
    bool hidden = false,
  }) {
    if (ssid.trim().isEmpty) throw const FormatException('Wi‑Fi SSID 不能为空');
    if (encryption != 'nopass' && password.isEmpty) {
      throw const FormatException('加密 Wi‑Fi 必须填写密码');
    }
    final type = switch (encryption) {
      'WEP' => 'WEP',
      'nopass' => 'nopass',
      _ => 'WPA',
    };
    return 'WIFI:T:$type;S:${_escapeWifi(ssid)};P:${_escapeWifi(password)};H:${hidden ? 'true' : 'false'};;';
  }

  String emailContent({
    required String address,
    String subject = '',
    String body = '',
  }) {
    final normalized = address.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw const FormatException('电子邮件地址格式错误');
    }
    return Uri(
      scheme: 'mailto',
      path: normalized,
      queryParameters: {
        if (subject.isNotEmpty) 'subject': subject,
        if (body.isNotEmpty) 'body': body,
      },
    ).toString();
  }

  String phoneContent(String number) {
    final normalized = number.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+?[0-9]{3,20}$').hasMatch(normalized)) {
      throw const FormatException('电话号码格式错误');
    }
    return 'tel:$normalized';
  }

  String smsContent({required String number, required String message}) {
    final normalized = number.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+?[0-9]{3,20}$').hasMatch(normalized)) {
      throw const FormatException('短信号码格式错误');
    }
    return 'SMSTO:$normalized:${message.replaceAll(':', r'\:')}';
  }

  Future<Uint8List> renderPng(
    QrMatrix matrix, {
    required int size,
    required int foregroundArgb,
    required int backgroundArgb,
  }) async {
    if (size < 128 || size > 4096)
      throw const FormatException('PNG 尺寸范围为 128～4096');
    const quietZone = 4;
    final modules = matrix.image.moduleCount;
    final cell = size / (modules + quietZone * 2);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      ui.Paint()..color = ui.Color(backgroundArgb),
    );
    final paint = ui.Paint()
      ..color = ui.Color(foregroundArgb)
      ..isAntiAlias = false;
    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        if (!matrix.image.isDark(row, col)) continue;
        canvas.drawRect(
          ui.Rect.fromLTRB(
            (col + quietZone) * cell,
            (row + quietZone) * cell,
            (col + quietZone + 1) * cell,
            (row + quietZone + 1) * cell,
          ),
          paint,
        );
      }
    }
    final image = await recorder.endRecording().toImage(size, size);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG 编码失败');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Uint8List renderSvg(
    QrMatrix matrix, {
    required int size,
    required int foregroundArgb,
    required int backgroundArgb,
  }) {
    if (size < 128 || size > 4096)
      throw const FormatException('SVG 尺寸范围为 128～4096');
    const quietZone = 4;
    final modules = matrix.image.moduleCount;
    final dimension = modules + quietZone * 2;
    final path = StringBuffer();
    for (var row = 0; row < modules; row++) {
      var col = 0;
      while (col < modules) {
        if (!matrix.image.isDark(row, col)) {
          col++;
          continue;
        }
        final start = col;
        while (col < modules && matrix.image.isDark(row, col)) col++;
        path.write(
          'M${start + quietZone} ${row + quietZone}h${col - start}v1H${start + quietZone}z',
        );
      }
    }
    final svg =
        '''<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" viewBox="0 0 $dimension $dimension" shape-rendering="crispEdges">
<rect width="$dimension" height="$dimension" fill="#${_rgbHex(backgroundArgb)}"/>
<path d="$path" fill="#${_rgbHex(foregroundArgb)}"/>
</svg>
''';
    return Uint8List.fromList(utf8.encode(svg));
  }

  int parseColor(String input) {
    var value = input.trim().replaceFirst('#', '');
    if (value.length == 3)
      value = value.split('').map((char) => '$char$char').join();
    if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(value)) {
      throw const FormatException('颜色必须为 #RRGGBB 或 #RGB');
    }
    return 0xff000000 | int.parse(value, radix: 16);
  }

  String _escapeWifi(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll(':', r'\:');

  String _rgbHex(int argb) =>
      (argb & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase();
}
