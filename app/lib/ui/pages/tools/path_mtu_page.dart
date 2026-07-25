import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/native_network_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../widgets/related_tool_actions.dart';

class PathMtuPage extends StatefulWidget {
  const PathMtuPage({super.key, required this.appState, this.initialHost});

  final AppState appState;
  final String? initialHost;

  @override
  State<PathMtuPage> createState() => _PathMtuPageState();
}

class _PathMtuPageState extends State<PathMtuPage> {
  final _host = TextEditingController(text: '223.5.5.5');
  final _mtu = TextEditingController(text: '1500');
  bool _running = false;
  bool _ipv6 = false;
  PathMtuResult? _result;
  String? _error;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _host.addListener(_saveDraft);
    _mtu.addListener(_saveDraft);
    unawaited(_restoreDraftAndLoadMtu());
  }

  @override
  void dispose() {
    if (_draftLoaded) unawaited(_drafts.save('tool.path_mtu', _draftValue()));
    _drafts.dispose();
    _host.dispose();
    _mtu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('路径 MTU 探测')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        TextField(
          controller: _host,
          enabled: !_running,
          decoration: const InputDecoration(
            label: LocalizedText('公网目标'),
            helper: LocalizedText('建议选择稳定且允许 ICMP 的目标；不要填路由器网关'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _mtu,
                enabled: !_running,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  label: LocalizedText('接口 MTU 上限'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: LocalizedText('IPv4')),
                ButtonSegment(value: true, label: LocalizedText('IPv6')),
              ],
              selected: {_ipv6},
              onSelectionChanged: _running
                  ? null
                  : (value) {
                      setState(() => _ipv6 = value.first);
                      _saveDraft();
                    },
            ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: const Icon(Icons.straighten),
          label: const LocalizedText('开始二分探测'),
        ),
        if (_running) const LinearProgressIndicator(),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LocalizedText(_error!),
            ),
          ),
        ],
        if (_result case final result?) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(
                    result.pathMtu == null
                        ? '未得到可确认的路径 MTU'
                        : '路径 MTU ≈ ${result.pathMtu} Bytes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LocalizedText(
                    '接口上限 ${result.interfaceMtu} · ${result.ipv6 ? 'IPv6' : 'IPv4'}',
                  ),
                  const SizedBox(height: 8),
                  if (result.pathMtu case final pathMtu?) ...[
                    _derivedValue(
                      '建议 TCP MSS',
                      '${(pathMtu - (result.ipv6 ? 60 : 40)).clamp(0, pathMtu)} Bytes',
                    ),
                    _derivedValue(
                      '最大 UDP Payload',
                      '${(pathMtu - (result.ipv6 ? 48 : 28)).clamp(0, pathMtu)} Bytes',
                    ),
                  ],
                  const SizedBox(height: 8),
                  const LocalizedText(
                    '提示：目标丢弃 ICMP、运营商限速或隧道动态变化都会影响结果，失败不等于该 MTU 一定不可用。',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          LocalizedText('探测过程', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final attempt in result.attempts)
            ListTile(
              dense: true,
              leading: Icon(
                attempt.success ? Icons.check_circle : Icons.cancel,
                color: attempt.success
                    ? const Color(0xFF168A5B)
                    : const Color(0xFFD34D4D),
              ),
              title: LocalizedText(
                'MTU ${attempt.mtu} · Payload ${attempt.payload}',
              ),
              trailing: LocalizedText(
                '${attempt.elapsedMs.toStringAsFixed(0)} ms',
              ),
            ),
          const SizedBox(height: 12),
          RelatedToolActions(
            currentToolId: 'path_mtu',
            appState: widget.appState,
            target: _host.text,
          ),
        ],
      ],
    ),
  );

  Future<void> _loadInterfaceMtu() async {
    try {
      final network = await NativeNetworkService().getNetworkContext();
      if (mounted && network.mtu > 0) _mtu.text = '${network.mtu}';
    } on Object {
      // The user can still provide an explicit MTU when native context is unavailable.
    }
  }

  Widget _derivedValue(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Expanded(child: LocalizedText(label)),
        SelectableText(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => Clipboard.setData(ClipboardData(text: value)),
          tooltip: context.tr('复制'),
          icon: const Icon(Icons.copy_outlined, size: 18),
        ),
      ],
    ),
  );

  Map<String, Object?> _draftValue() => {
    'host': _host.text,
    'mtu': _mtu.text,
    'ipv6': _ipv6,
  };

  Future<void> _restoreDraftAndLoadMtu() async {
    final draft = await _drafts.load('tool.path_mtu');
    if (!mounted) return;
    if (draft != null) {
      _host.text = draft.payload['host']?.toString() ?? _host.text;
      _mtu.text = draft.payload['mtu']?.toString() ?? _mtu.text;
      _ipv6 = draft.payload['ipv6'] == true;
    } else {
      await _loadInterfaceMtu();
    }
    final initialHost = widget.initialHost?.trim();
    if (initialHost != null && initialHost.isNotEmpty) _host.text = initialHost;
    if (mounted) setState(() {});
    _draftLoaded = true;
  }

  void _saveDraft() {
    if (_draftLoaded) _drafts.scheduleSave('tool.path_mtu', _draftValue());
  }

  Future<void> _run() async {
    final mtu = int.tryParse(_mtu.text.trim());
    if (mtu == null || mtu < 576 || mtu > 65535) {
      setState(() => _error = '接口 MTU 范围应为 576～65535');
      return;
    }
    setState(() {
      _running = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await NativeNetworkService().probePathMtu(
        host: _host.text.trim(),
        interfaceMtu: mtu,
        ipv6: _ipv6,
      );
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}
