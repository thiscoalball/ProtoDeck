import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/ip_tools_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class IpToolsPage extends StatefulWidget {
  const IpToolsPage({super.key, this.appState, this.initialInput});
  final AppState? appState;
  final String? initialInput;
  @override
  State<IpToolsPage> createState() => _IpToolsPageState();
}

class _IpToolsPageState extends State<IpToolsPage> {
  final _service = IpToolsService();
  final _input = TextEditingController(text: '192.168.1.1');
  final _prefix = TextEditingController(text: '64:ff9b::/96');
  String _mode = 'classify';
  String _output = '';
  ToolDraftRepository? _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    final appState = widget.appState;
    if (appState == null) {
      final initial = widget.initialInput?.trim();
      if (initial != null && initial.isNotEmpty) _input.text = initial;
      return;
    }
    _drafts = ToolDraftRepository(appState.database);
    _input.addListener(_scheduleDraft);
    _prefix.addListener(_scheduleDraft);
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    final draft = await _drafts?.load('tool.ip_tools');
    if (!mounted) return;
    if (draft != null) {
      _input.text = draft.payload['input']?.toString() ?? _input.text;
      _prefix.text = draft.payload['prefix']?.toString() ?? _prefix.text;
      setState(() => _mode = draft.payload['mode']?.toString() ?? _mode);
    }
    final initial = widget.initialInput?.trim();
    if (initial != null && initial.isNotEmpty) _input.text = initial;
    _draftLoaded = true;
  }

  Map<String, Object?> _draftSnapshot() => {
    'input': _input.text,
    'prefix': _prefix.text,
    'mode': _mode,
  };

  void _scheduleDraft() {
    if (_draftLoaded) {
      _drafts?.scheduleSave('tool.ip_tools', _draftSnapshot());
    }
  }

  @override
  void dispose() {
    if (_draftLoaded && _drafts != null) {
      unawaited(_drafts!.save('tool.ip_tools', _draftSnapshot()));
    }
    _drafts?.dispose();
    _input.dispose();
    _prefix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('IP 与 IPv6 转换'),
      actions: [
        IconButton(
          tooltip: context.tr('恢复默认'),
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt_rounded),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _mode,
          decoration: const InputDecoration(label: LocalizedText('功能')),
          items:
              const {
                    'classify': '地址分类',
                    'v4v6': 'IPv4 → IPv6',
                    'v6v4': 'IPv6 → IPv4',
                    'v6format': 'IPv6 格式化',
                    'v4format': 'IPv4 数值表示',
                    'v6subnet': 'IPv6 子网计算',
                  }.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: LocalizedText(e.value),
                    ),
                  )
                  .toList(),
          onChanged: (v) => setState(() {
            _mode = v!;
            _output = '';
            _input.text = switch (v) {
              'v6format' => '2001:db8::1',
              'v6v4' => '::ffff:192.0.2.1',
              'v6subnet' => '2001:db8::1/48',
              _ => '192.168.1.1',
            };
            _scheduleDraft();
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            label: const LocalizedText('地址或 CIDR'),
            suffixIcon: IconButton(
              tooltip: context.tr('粘贴'),
              onPressed: _pasteInput,
              icon: const Icon(Icons.content_paste_rounded),
            ),
          ),
        ),
        if (_mode == 'v4v6' || _mode == 'v6v4') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _prefix,
            decoration: const InputDecoration(
              label: LocalizedText('NAT64 /96 前缀'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _run,
          icon: const Icon(Icons.transform),
          label: const LocalizedText('计算'),
        ),
        const SizedBox(height: 16),
        if (_output.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: LocalizedText(
                          '结果',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: _output)),
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
                  for (final row in _outputRows())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            children: [
                              if (row.$1.isNotEmpty) ...[
                                SizedBox(
                                  width: 108,
                                  child: LocalizedText(
                                    row.$1,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              Expanded(
                                child: SelectableText(
                                  context.tr(row.$2),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    height: 1.45,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: context.tr('复制'),
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: context.tr(row.$2)),
                                ),
                                icon: const Icon(
                                  Icons.content_copy_rounded,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  void _run() {
    try {
      final result = switch (_mode) {
        'classify' => _classify(),
        'v4v6' =>
          _service
              .ipv4ToIpv6(_input.text, nat64Prefix: _prefix.text)
              .entries
              .map((e) => '${e.key}\n${e.value}')
              .join('\n\n'),
        'v6v4' => _extract(),
        'v6format' => _v6Format(),
        'v4format' => _v4Format(),
        'v6subnet' => _v6Subnet(),
        _ => '',
      };
      setState(() => _output = result);
    } on Object catch (e) {
      setState(() => _output = '错误：$e');
    }
  }

  String _classify() {
    final r = _service.classify(_input.text);
    return '地址：${r.address}\n版本：IPv${r.version}\n类别：${r.category}\n公网：${r.isPublic ? '是' : '否'}\n说明：${r.description}';
  }

  String _extract() {
    final r = _service.extractIpv4(_input.text, nat64Prefix: _prefix.text);
    return r == null ? '未识别到受支持的内嵌 IPv4 格式' : '格式：${r.format}\nIPv4：${r.ipv4}';
  }

  String _v6Format() {
    final r = _service.formatIpv6(_input.text);
    return '压缩\n${r.compressed}\n\n展开\n${r.expanded}\n\nip6.arpa\n${r.reverseDns}\n\n128 位十进制\n${r.decimal}\n\n十六进制\n${r.hexadecimal}';
  }

  String _v4Format() {
    final r = _service.representIpv4(_input.text);
    return 'IPv4：${r.address}\n十进制：${r.decimal}\n十六进制：${r.hexadecimal}\n二进制：${r.binary}';
  }

  String _v6Subnet() {
    final r = _service.calculateIpv6Subnet(_input.text);
    return '网络：${r.network}\n起始：${r.firstAddress}\n结束：${r.lastAddress}\n总地址数：${_service.formatBigInt(r.totalAddresses)}${r.slash64Networks == null ? '' : '\n/64 子网数：${_service.formatBigInt(r.slash64Networks!)}'}';
  }

  List<(String, String)> _outputRows() {
    final lines = _output
        .split('\n')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final result = <(String, String)>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final separator = line.indexOf('：');
      if (separator > 0) {
        result.add((
          line.substring(0, separator),
          line.substring(separator + 1),
        ));
      } else if (index + 1 < lines.length && !lines[index + 1].contains('：')) {
        result.add((line, lines[++index]));
      } else {
        result.add(('', line));
      }
    }
    return result;
  }

  Future<void> _pasteInput() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text?.isNotEmpty == true) _input.text = text!;
  }

  Future<void> _reset() async {
    await _drafts?.reset('tool.ip_tools');
    if (!mounted) return;
    setState(() {
      _mode = 'classify';
      _input.text = '192.168.1.1';
      _prefix.text = '64:ff9b::/96';
      _output = '';
    });
  }
}
