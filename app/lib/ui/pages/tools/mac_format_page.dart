import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/mac_format_service.dart';

class MacFormatPage extends StatefulWidget {
  const MacFormatPage({super.key});

  @override
  State<MacFormatPage> createState() => _MacFormatPageState();
}

class _MacFormatPageState extends State<MacFormatPage> {
  final _input = TextEditingController(text: 'aabb.ccdd.eeff');
  bool _uppercase = false;
  MacFormatResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _format();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('MAC 格式化')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        TextField(
          controller: _input,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(
            label: LocalizedText('任意 MAC 格式'),
            hintText: 'AA:BB:CC:DD:EE:FF / AABB.CCDD.EEFF',
            helper: LocalizedText('支持冒号、连字符、Cisco 点分及无分隔符'),
          ),
          onChanged: (_) => _format(),
          onSubmitted: (_) => _format(),
        ),
        const SizedBox(height: 10),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: LocalizedText('小写 aa:bb')),
            ButtonSegment(value: true, label: LocalizedText('大写 AA:BB')),
          ],
          selected: {_uppercase},
          onSelectionChanged: (value) {
            setState(() => _uppercase = value.first);
            _format();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          LocalizedText(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_result case final result?) ...[
          const SizedBox(height: 14),
          _formatCard('冒号格式 · Linux', result.colon, Icons.code),
          _formatCard(
            '连字符格式 · Windows',
            result.hyphen,
            Icons.desktop_windows_outlined,
          ),
          _formatCard('点分格式 · Cisco', result.cisco, Icons.router_outlined),
          _formatCard('无分隔符', result.plain, Icons.text_fields),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _copy(
              [
                result.colon,
                result.hyphen,
                result.cisco,
                result.plain,
              ].join('\n'),
            ),
            icon: const Icon(Icons.copy_all),
            label: const LocalizedText('复制全部格式'),
          ),
        ],
      ],
    ),
  );

  Widget _formatCard(String title, String value, IconData icon) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: LocalizedText(title),
      subtitle: SelectableText(
        value,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: IconButton(
        onPressed: () => _copy(value),
        tooltip: context.tr('复制'),
        icon: const Icon(Icons.copy),
      ),
    ),
  );

  void _format() {
    try {
      final result = MacFormatService().format(
        _input.text,
        uppercase: _uppercase,
      );
      setState(() {
        _result = result;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _result = null;
        _error = error.message;
      });
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('已复制')));
  }
}
