import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/subnet_service.dart';
import '../../../state/app_state.dart';

class SubnetPage extends StatefulWidget {
  const SubnetPage({super.key, required this.appState});
  final AppState appState;

  @override
  State<SubnetPage> createState() => _SubnetPageState();
}

class _SubnetPageState extends State<SubnetPage> {
  final _input = TextEditingController(text: '192.168.1.10/24');
  SubnetResult? _result;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('IPv4 子网计算')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _input,
            decoration: const InputDecoration(
              labelText: 'IP/CIDR',
              hintText: '192.168.1.10/24',
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
          if (_result != null) ...[
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
              onPressed: _copy,
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
        _error = error.message;
      });
    }
  }

  String _text(SubnetResult result) =>
      '网络地址: ${result.network}\n广播地址: ${result.broadcast}\n子网掩码: ${result.mask}\n通配符掩码: ${result.wildcardMask}\n地址范围: ${result.firstHost} - ${result.lastHost}\n地址总数: ${result.totalAddresses}\n可用主机: ${result.usableHosts}';
  void _copy() => Clipboard.setData(ClipboardData(text: _text(_result!)));

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
