import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/wildcard_mask_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class WildcardMaskPage extends StatefulWidget {
  const WildcardMaskPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<WildcardMaskPage> createState() => _WildcardMaskPageState();
}

class _WildcardMaskPageState extends State<WildcardMaskPage> {
  final _service = WildcardMaskService();
  final _input = TextEditingController(text: '255.255.255.0');
  final _address = TextEditingController(text: '192.168.1.10');
  WildcardInputType _type = WildcardInputType.subnetMask;
  WildcardMaskResult? _result;
  String? _error;
  WildcardMatchRange? _range;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _input.addListener(_saveDraft);
    _address.addListener(_saveDraft);
    _calculate();
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    if (_draftLoaded) unawaited(_drafts.save('tool.wildcard', _draftValue()));
    _drafts.dispose();
    _input.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('通配符掩码')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        SegmentedButton<WildcardInputType>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: WildcardInputType.subnetMask,
              label: LocalizedText('子网掩码'),
            ),
            ButtonSegment(
              value: WildcardInputType.wildcardMask,
              label: LocalizedText('通配符'),
            ),
            ButtonSegment(
              value: WildcardInputType.cidr,
              label: LocalizedText('CIDR'),
            ),
          ],
          selected: {_type},
          onSelectionChanged: (value) => _changeType(value.first),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _input,
          keyboardType: _type == WildcardInputType.cidr
              ? TextInputType.number
              : const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: context.tr(switch (_type) {
              WildcardInputType.subnetMask => '子网掩码',
              WildcardInputType.wildcardMask => '通配符掩码',
              WildcardInputType.cidr => 'CIDR 前缀',
            }),
            hintText: switch (_type) {
              WildcardInputType.subnetMask => '255.255.255.0',
              WildcardInputType.wildcardMask => '0.0.0.255',
              WildcardInputType.cidr => '/24',
            },
          ),
          onSubmitted: (_) => _calculate(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(
            label: LocalizedText('用于匹配范围的 IPv4 地址'),
            hintText: '192.168.1.10',
            helper: LocalizedText('用于生成网络范围和 ACL / OSPF 地址表达式'),
          ),
          onSubmitted: (_) => _calculate(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _calculate,
          icon: const Icon(Icons.calculate_outlined),
          label: const LocalizedText('计算'),
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
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(
                    '/${result.prefix}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _resultBlock('子网掩码', result.subnetMask, result.subnetBinary),
                  const Divider(height: 24),
                  _resultBlock(
                    '通配符掩码',
                    result.wildcardMask,
                    result.wildcardBinary,
                  ),
                  if (_range case final range?) ...[
                    const Divider(height: 24),
                    _resultBlock(
                      '匹配地址范围',
                      '${range.networkAddress} – ${range.lastAddress}',
                      'ACL / OSPF  ${range.aclAddressWildcard}',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        LocalizedText(
          '常用速查',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var prefix = 24; prefix <= 30; prefix++) ...[
                _quickRow(prefix),
                if (prefix != 30)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _resultBlock(String label, String decimal, String binary) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: LocalizedText(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: () => _copy(decimal),
            tooltip: context.tr('复制'),
            icon: const Icon(Icons.copy, size: 20),
          ),
        ],
      ),
      SelectableText(
        decimal,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      SelectableText(
        binary,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: Color(0xFF5D7183),
        ),
      ),
    ],
  );

  Widget _quickRow(int prefix) {
    final result = _service.calculate('$prefix', WildcardInputType.cidr);
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 42,
        child: LocalizedText(
          '/$prefix',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      title: LocalizedText(
        result.wildcardMask,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      subtitle: LocalizedText(
        result.subnetMask,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      trailing: const Icon(Icons.north_west, size: 18),
      onTap: () {
        _type = WildcardInputType.cidr;
        _input.text = '$prefix';
        _calculate();
        _saveDraft();
      },
    );
  }

  void _changeType(WildcardInputType type) {
    setState(() {
      _type = type;
      _input.text = switch (type) {
        WildcardInputType.subnetMask => '255.255.255.0',
        WildcardInputType.wildcardMask => '0.0.0.255',
        WildcardInputType.cidr => '24',
      };
    });
    _calculate();
    _saveDraft();
  }

  void _calculate() {
    try {
      final result = _service.calculate(_input.text, _type);
      final range = _address.text.trim().isEmpty
          ? null
          : _service.matchRange(_address.text, result);
      setState(() {
        _result = result;
        _range = range;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _result = null;
        _range = null;
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

  Map<String, Object?> _draftValue() => {
    'input': _input.text,
    'address': _address.text,
    'type': _type.name,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.wildcard');
    if (!mounted) return;
    if (draft != null) {
      _input.text = draft.payload['input']?.toString() ?? _input.text;
      _address.text = draft.payload['address']?.toString() ?? _address.text;
      _type = WildcardInputType.values.firstWhere(
        (value) => value.name == draft.payload['type'],
        orElse: () => _type,
      );
      _calculate();
    }
    _draftLoaded = true;
  }

  void _saveDraft() {
    if (_draftLoaded) {
      _drafts.scheduleSave('tool.wildcard', _draftValue());
    }
  }
}
