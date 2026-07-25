import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/subnet_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class SubnetPage extends StatefulWidget {
  const SubnetPage({super.key, required this.appState});
  final AppState appState;

  @override
  State<SubnetPage> createState() => _SubnetPageState();
}

class _SubnetPageState extends State<SubnetPage> {
  final _input = TextEditingController(text: '192.168.1.10/24');
  late final ToolDraftRepository _drafts = ToolDraftRepository(
    widget.appState.database,
  );
  SubnetResult? _result;
  Ipv6SubnetResult? _ipv6Result;
  String? _error;
  bool _ipv6 = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(_saveDraft);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    unawaited(_drafts.flush('subnet'));
    _drafts.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('子网计算'),
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
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('IPv4')),
              ButtonSegment(value: true, label: Text('IPv6')),
            ],
            selected: {_ipv6},
            onSelectionChanged: (value) => _changeFamily(value.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            decoration: InputDecoration(
              labelText: 'IP/CIDR',
              hintText: _ipv6 ? '2001:db8::1/64' : '192.168.1.10/24',
            ),
            onSubmitted: (_) => _calculate(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _calculate,
            icon: const Icon(Icons.calculate),
            label: const LocalizedText('计算'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: LocalizedText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!_ipv6 && _result != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _row('输入', _result!.input),
                    _row('网络地址', _result!.network),
                    _row('广播地址', _result!.broadcast),
                    _row('子网掩码', _result!.mask),
                    _row('通配符掩码', _result!.wildcardMask),
                    _row('首个可用', _result!.firstHost),
                    _row('最后可用', _result!.lastHost),
                    _row('地址总数', '${_result!.totalAddresses}'),
                    _row('可用主机', '${_result!.usableHosts}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _copyIpv4,
              icon: const Icon(Icons.copy),
              label: const LocalizedText('复制结果'),
            ),
          ],
          if (_ipv6 && _ipv6Result != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _row('输入', _ipv6Result!.input),
                    _row('网络地址', _ipv6Result!.network),
                    _row('起始地址', _ipv6Result!.firstAddress),
                    _row('结束地址', _ipv6Result!.lastAddress),
                    _row(
                      '地址总数',
                      SubnetService().formatCount(_ipv6Result!.totalAddresses),
                    ),
                    if (_ipv6Result!.slash64Networks case final count?)
                      _row('/64 子网数量', SubnetService().formatCount(count)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _copyIpv6,
              icon: const Icon(Icons.copy),
              label: const LocalizedText('复制结果'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: LocalizedText(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: SelectableText(value)),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: context.tr('复制 $label'),
              onPressed: () => _copyValue(label, value),
              icon: const Icon(Icons.content_copy_rounded, size: 18),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _calculate() async {
    try {
      if (_ipv6) {
        final result = SubnetService().calculateIpv6(_input.text);
        setState(() {
          _ipv6Result = result;
          _result = null;
          _error = null;
        });
        await widget.appState.addHistory(
          tool: 'subnet',
          title: 'IPv6 子网计算 ${result.input}',
          summary: result.network,
          detail: _ipv6Text(result),
          success: true,
        );
        return;
      }
      final result = SubnetService().calculate(_input.text);
      setState(() {
        _result = result;
        _error = null;
      });
      await widget.appState.addHistory(
        tool: 'subnet',
        title: '子网计算 ${result.input}',
        summary: result.network,
        detail: _text(result),
        success: true,
      );
    } on FormatException catch (error) {
      setState(() {
        _result = null;
        _ipv6Result = null;
        _error = error.message;
      });
    }
  }

  String _text(SubnetResult result) =>
      '网络地址: ${result.network}\n广播地址: ${result.broadcast}\n子网掩码: ${result.mask}\n通配符掩码: ${result.wildcardMask}\n地址范围: ${result.firstHost} - ${result.lastHost}\n地址总数: ${result.totalAddresses}\n可用主机: ${result.usableHosts}';
  String _ipv6Text(Ipv6SubnetResult result) =>
      '网络地址: ${result.network}\n地址范围: ${result.firstAddress} - ${result.lastAddress}\n地址总数: ${SubnetService().formatCount(result.totalAddresses)}${result.slash64Networks == null ? '' : '\n/64 子网数量: ${SubnetService().formatCount(result.slash64Networks!)}'}';

  void _copyIpv4() => Clipboard.setData(ClipboardData(text: _text(_result!)));
  void _copyIpv6() =>
      Clipboard.setData(ClipboardData(text: _ipv6Text(_ipv6Result!)));

  void _changeFamily(bool ipv6) {
    setState(() {
      _ipv6 = ipv6;
      _result = null;
      _ipv6Result = null;
      _error = null;
      _input.text = ipv6 ? '2001:db8::1/64' : '192.168.1.10/24';
    });
    _saveDraft();
  }

  void _saveDraft() {
    _drafts.scheduleSave('subnet', {'input': _input.text, 'ipv6': _ipv6});
  }

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('subnet');
    if (!mounted || draft == null) return;
    final ipv6 = draft.payload['ipv6'] == true;
    setState(() {
      _ipv6 = ipv6;
      _input.text =
          draft.payload['input']?.toString() ??
          (ipv6 ? '2001:db8::1/64' : '192.168.1.10/24');
    });
  }

  Future<void> _reset() async {
    await _drafts.reset('subnet');
    if (!mounted) return;
    setState(() {
      _ipv6 = false;
      _input.text = '192.168.1.10/24';
      _result = null;
      _ipv6Result = null;
      _error = null;
    });
  }

  void _copyValue(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        content: LocalizedText('已复制 $label'),
      ),
    );
  }
}
