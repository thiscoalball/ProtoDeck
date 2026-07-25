import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/native_network_service.dart';

class PathMtuPage extends StatefulWidget {
  const PathMtuPage({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadInterfaceMtu();
  }

  @override
  void dispose() {
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
                  : (value) => setState(() => _ipv6 = value.first),
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
        ],
      ],
    ),
  );

  Future<void> _loadInterfaceMtu() async {
    try {
      final context = await NativeNetworkService().getNetworkContext();
      if (context.mtu > 0) _mtu.text = '${context.mtu}';
    } on Object {
      // The user can still provide an explicit MTU when native context is unavailable.
    }
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
