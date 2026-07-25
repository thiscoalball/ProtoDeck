import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/network_intelligence_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../widgets/related_tool_actions.dart';

class IpOwnershipPage extends StatefulWidget {
  const IpOwnershipPage({
    super.key,
    required this.appState,
    this.initialTarget,
  });

  final AppState appState;
  final String? initialTarget;

  @override
  State<IpOwnershipPage> createState() => _IpOwnershipPageState();
}

class _IpOwnershipPageState extends State<IpOwnershipPage> {
  final _target = TextEditingController(text: 'baidu.com');
  final _endpoint = TextEditingController(text: 'https://rdap.org/ip/');
  bool _running = false;
  IpOwnershipResult? _result;
  String? _error;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _target.addListener(_saveDraft);
    _endpoint.addListener(_saveDraft);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    if (_draftLoaded) {
      unawaited(_drafts.save('tool.ownership', _draftValue()));
    }
    _drafts.dispose();
    _target.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('RDAP / ASN 归属')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        TextField(
          controller: _target,
          enabled: !_running,
          decoration: const InputDecoration(label: LocalizedText('公网 IP 或域名')),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const LocalizedText('RDAP Provider'),
          children: [
            TextField(
              controller: _endpoint,
              enabled: !_running,
              decoration: const InputDecoration(
                labelText: 'Endpoint',
                helper: LocalizedText('必须是以 / 结尾的 RDAP IP 查询地址'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: const Icon(Icons.account_tree_outlined),
          label: const LocalizedText('查询注册与路由归属'),
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
                    result.address,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _row('ASN', result.asn == null ? '未获取' : 'AS${result.asn}'),
                  _row('路由名称', result.asName ?? '—'),
                  _row('国家/地区', result.asCountry ?? result.country ?? '—'),
                  _row('RIR', result.registry ?? '—'),
                  const Divider(height: 24),
                  _row('网络名称', result.name ?? '—'),
                  _row('Handle', result.handle ?? '—'),
                  _row('类型', result.type ?? '—'),
                  _row(
                    '地址范围',
                    '${result.startAddress ?? '—'} — ${result.endAddress ?? '—'}',
                  ),
                  _row(
                    'CIDR',
                    result.cidrs.isEmpty ? '服务未提供' : result.cidrs.join(', '),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    result.rdapEndpoint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          RelatedToolActions(
            currentToolId: 'ownership',
            appState: widget.appState,
            target: result.address,
          ),
        ],
      ],
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: LocalizedText(
            label,
            style: const TextStyle(color: Color(0xFF5E6B78)),
          ),
        ),
        Expanded(child: SelectableText(value)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value == '—'
              ? null
              : () => Clipboard.setData(ClipboardData(text: value)),
          tooltip: context.tr('复制'),
          icon: const Icon(Icons.copy_outlined, size: 18),
        ),
      ],
    ),
  );

  Future<void> _run() async {
    final base = _endpoint.text.trim();
    if (!base.startsWith('https://') || !base.endsWith('/')) {
      setState(() => _error = 'RDAP Endpoint 必须使用 HTTPS 且以 / 结尾');
      return;
    }
    setState(() {
      _running = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await IpOwnershipService().lookup(
        _target.text,
        rdapBase: base,
      );
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Map<String, Object?> _draftValue() => {
    'target': _target.text,
    'endpoint': _endpoint.text,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.ownership');
    if (!mounted) return;
    if (draft != null) {
      _target.text = draft.payload['target']?.toString() ?? _target.text;
      _endpoint.text = draft.payload['endpoint']?.toString() ?? _endpoint.text;
    }
    final initialTarget = widget.initialTarget?.trim();
    if (initialTarget != null && initialTarget.isNotEmpty) {
      _target.text = initialTarget;
    }
    _draftLoaded = true;
  }

  void _saveDraft() {
    if (_draftLoaded) _drafts.scheduleSave('tool.ownership', _draftValue());
  }
}
