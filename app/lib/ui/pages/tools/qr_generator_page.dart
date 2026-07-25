import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/qr_code_service.dart';

class QrGeneratorPage extends StatefulWidget {
  const QrGeneratorPage({super.key});

  @override
  State<QrGeneratorPage> createState() => _QrGeneratorPageState();
}

class _QrGeneratorPageState extends State<QrGeneratorPage> {
  final _service = QrCodeService();
  final _primary = TextEditingController(text: 'https://example.com');
  final _secondary = TextEditingController();
  final _tertiary = TextEditingController();
  final _foreground = TextEditingController(text: '#102A43');
  final _background = TextEditingController(text: '#FFFFFF');
  QrContentType _type = QrContentType.url;
  String _wifiEncryption = 'WPA';
  bool _wifiHidden = false;
  int _size = 512;
  QrMatrix? _matrix;
  String? _error;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _primary.dispose();
    _secondary.dispose();
    _tertiary.dispose();
    _foreground.dispose();
    _background.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foreground = _safeColor(_foreground.text, const Color(0xFF102A43));
    final background = _safeColor(_background.text, Colors.white);
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('二维码生成器')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          DropdownButtonFormField<QrContentType>(
            initialValue: _type,
            decoration: const InputDecoration(label: LocalizedText('内容类型')),
            items:
                const {
                      QrContentType.url: ('URL', Icons.link),
                      QrContentType.wifi: ('Wi‑Fi', Icons.wifi),
                      QrContentType.email: ('电子邮件', Icons.email_outlined),
                      QrContentType.phone: ('电话', Icons.phone_outlined),
                      QrContentType.sms: ('短信', Icons.sms_outlined),
                    }.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Row(
                          children: [
                            Icon(entry.value.$2, size: 19),
                            const SizedBox(width: 8),
                            LocalizedText(entry.value.$1),
                          ],
                        ),
                      ),
                    )
                    .toList(),
            onChanged: (value) => _changeType(value!),
          ),
          const SizedBox(height: 12),
          ..._contentFields(),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.qr_code_2),
            label: const LocalizedText('生成二维码'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            LocalizedText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_matrix case final matrix?) ...[
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: CustomPaint(
                  size: const Size.square(260),
                  painter: _QrMatrixPainter(
                    matrix: matrix,
                    foreground: foreground,
                    background: background,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const LocalizedText('样式与导出'),
              initiallyExpanded: true,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _foreground,
                        decoration: const InputDecoration(
                          label: LocalizedText('二维码颜色'),
                          hintText: '#102A43',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _background,
                        decoration: const InputDecoration(
                          label: LocalizedText('背景颜色'),
                          hintText: '#FFFFFF',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _palette('#102A43', '#FFFFFF'),
                    _palette('#1769AA', '#F4F9FD'),
                    _palette('#00695C', '#E8F5F2'),
                    _palette('#000000', '#FFFFFF'),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _size,
                  decoration: const InputDecoration(
                    label: LocalizedText('导出尺寸'),
                  ),
                  items: const [256, 512, 1024, 2048]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: LocalizedText('$value × $value px'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _size = value!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _exporting ? null : () => _export(false),
                        icon: const Icon(Icons.image_outlined),
                        label: const LocalizedText('保存 PNG'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exporting ? null : () => _export(true),
                        icon: const Icon(Icons.data_object),
                        label: const LocalizedText('保存 SVG'),
                      ),
                    ),
                  ],
                ),
                if (_exporting)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
            Card(
              child: ListTile(
                title: const LocalizedText('编码内容'),
                subtitle: SelectableText(matrix.content, maxLines: 4),
                trailing: IconButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: matrix.content)),
                  icon: const Icon(Icons.copy),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _contentFields() => switch (_type) {
    QrContentType.url => [
      TextField(
        controller: _primary,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'URL',
          hintText: 'https://example.com',
        ),
      ),
    ],
    QrContentType.wifi => [
      TextField(
        controller: _primary,
        decoration: const InputDecoration(labelText: 'SSID'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _secondary,
        obscureText: true,
        decoration: const InputDecoration(label: LocalizedText('密码')),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _wifiEncryption,
        decoration: const InputDecoration(label: LocalizedText('加密方式')),
        items: const {'WPA': 'WPA/WPA2/WPA3', 'WEP': 'WEP', 'nopass': '无密码'}
            .entries
            .map(
              (entry) => DropdownMenuItem(
                value: entry.key,
                child: LocalizedText(entry.value),
              ),
            )
            .toList(),
        onChanged: (value) => setState(() => _wifiEncryption = value!),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _wifiHidden,
        onChanged: (value) => setState(() => _wifiHidden = value),
        title: const LocalizedText('隐藏网络'),
      ),
    ],
    QrContentType.email => [
      TextField(
        controller: _primary,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(label: LocalizedText('收件人')),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _secondary,
        decoration: const InputDecoration(label: LocalizedText('主题（可选）')),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _tertiary,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(label: LocalizedText('正文（可选）')),
      ),
    ],
    QrContentType.phone => [
      TextField(
        controller: _primary,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(label: LocalizedText('电话号码')),
      ),
    ],
    QrContentType.sms => [
      TextField(
        controller: _primary,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(label: LocalizedText('电话号码')),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _secondary,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(label: LocalizedText('短信内容')),
      ),
    ],
  };

  Widget _palette(String foreground, String background) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => setState(() {
      _foreground.text = foreground;
      _background.text = background;
    }),
    child: Container(
      width: 52,
      height: 36,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: ColoredBox(color: _safeColor(foreground, Colors.black)),
          ),
          Expanded(
            child: ColoredBox(color: _safeColor(background, Colors.white)),
          ),
        ],
      ),
    ),
  );

  void _changeType(QrContentType type) {
    setState(() {
      _type = type;
      _primary.text = switch (type) {
        QrContentType.url => 'https://example.com',
        QrContentType.wifi => '',
        QrContentType.email => '',
        QrContentType.phone || QrContentType.sms => '',
      };
      _secondary.clear();
      _tertiary.clear();
      _matrix = null;
      _error = null;
    });
  }

  void _generate() {
    try {
      final content = switch (_type) {
        QrContentType.url => _service.urlContent(_primary.text),
        QrContentType.wifi => _service.wifiContent(
          ssid: _primary.text,
          password: _secondary.text,
          encryption: _wifiEncryption,
          hidden: _wifiHidden,
        ),
        QrContentType.email => _service.emailContent(
          address: _primary.text,
          subject: _secondary.text,
          body: _tertiary.text,
        ),
        QrContentType.phone => _service.phoneContent(_primary.text),
        QrContentType.sms => _service.smsContent(
          number: _primary.text,
          message: _secondary.text,
        ),
      };
      final foreground = _service.parseColor(_foreground.text);
      final background = _service.parseColor(_background.text);
      if ((foreground & 0xffffff) == (background & 0xffffff))
        throw const FormatException('二维码颜色不能与背景颜色相同');
      setState(() {
        _matrix = _service.create(content);
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _matrix = null;
        _error = '$error'.replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _export(bool svg) async {
    final matrix = _matrix;
    if (matrix == null) return;
    final dialogTitle = context.tr('保存二维码');
    setState(() => _exporting = true);
    try {
      final foreground = _service.parseColor(_foreground.text);
      final background = _service.parseColor(_background.text);
      if ((foreground & 0xffffff) == (background & 0xffffff)) {
        throw const FormatException('二维码颜色不能与背景颜色相同');
      }
      final bytes = svg
          ? _service.renderSvg(
              matrix,
              size: _size,
              foregroundArgb: foreground,
              backgroundArgb: background,
            )
          : await _service.renderPng(
              matrix,
              size: _size,
              foregroundArgb: foreground,
              backgroundArgb: background,
            );
      final extension = svg ? 'svg' : 'png';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: 'protodeck_qr.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
      if (path != null && mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText('已保存：$path')));
    } on Object catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText('导出失败：$error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Color _safeColor(String input, Color fallback) {
    try {
      return Color(_service.parseColor(input));
    } on Object {
      return fallback;
    }
  }
}

class _QrMatrixPainter extends CustomPainter {
  const _QrMatrixPainter({
    required this.matrix,
    required this.foreground,
    required this.background,
  });
  final QrMatrix matrix;
  final Color foreground;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    const quiet = 4;
    final modules = matrix.image.moduleCount;
    final cell = size.shortestSide / (modules + quiet * 2);
    final paint = Paint()
      ..color = foreground
      ..isAntiAlias = false;
    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        if (!matrix.image.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH((col + quiet) * cell, (row + quiet) * cell, cell, cell),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrMatrixPainter oldDelegate) =>
      oldDelegate.matrix.content != matrix.content ||
      oldDelegate.foreground != foreground ||
      oldDelegate.background != background;
}
