import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/mac_format_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../widgets/related_tool_actions.dart';

class MacFormatPage extends StatefulWidget {
  const MacFormatPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<MacFormatPage> createState() => _MacFormatPageState();
}

class _MacFormatPageState extends State<MacFormatPage> {
  final _input = TextEditingController(text: 'aabb.ccdd.eeff');
  bool _uppercase = false;
  MacFormatResult? _result;
  String? _error;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _input.addListener(_saveDraft);
    _format();
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    if (_draftLoaded) {
      unawaited(
        _drafts.save('tool.mac_format', {
          'input': _input.text,
          'uppercase': _uppercase,
        }),
      );
    }
    _drafts.dispose();
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
            _saveDraft();
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
          _formatCard(
            'Modified EUI-64',
            result.modifiedEui64,
            Icons.account_tree_outlined,
          ),
          _formatCard(
            'IPv6 链路本地地址',
            result.linkLocalIpv6,
            Icons.language_outlined,
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const LocalizedText('MAC 地址属性'),
              subtitle: LocalizedText(
                '${result.isMulticast ? '组播' : '单播'} · '
                '${result.isLocallyAdministered ? '本地管理' : '全局管理'}',
              ),
            ),
          ),
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
          const SizedBox(height: 12),
          RelatedToolActions(
            currentToolId: 'mac_format',
            appState: widget.appState,
            target: result.colon,
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

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.mac_format');
    if (!mounted) return;
    if (draft != null) {
      _input.text = draft.payload['input']?.toString() ?? _input.text;
      _uppercase = draft.payload['uppercase'] == true;
      _format();
    }
    _draftLoaded = true;
  }

  void _saveDraft() {
    if (!_draftLoaded) return;
    _drafts.scheduleSave('tool.mac_format', {
      'input': _input.text,
      'uppercase': _uppercase,
    });
  }
}
