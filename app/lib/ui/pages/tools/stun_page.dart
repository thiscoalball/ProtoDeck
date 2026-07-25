import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/stun_service.dart';

class StunPage extends StatefulWidget {
  const StunPage({super.key});

  @override
  State<StunPage> createState() => _StunPageState();
}

class _StunPageState extends State<StunPage> {
  final _server = TextEditingController(text: 'stun.miwifi.com');
  final _port = TextEditingController(text: '3478');
  bool _running = false;
  StunBindingResult? _result;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('STUN 映射检测')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _server,
                enabled: !_running,
                decoration: const InputDecoration(
                  label: LocalizedText('STUN 服务器'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _port,
                enabled: !_running,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(label: LocalizedText('端口')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: const Icon(Icons.compare_arrows),
          label: const LocalizedText('发送 Binding Request'),
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
                    '${result.mappedAddress}:${result.mappedPort}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LocalizedText(
                    'STUN：${result.server} → ${result.serverAddress}',
                  ),
                  LocalizedText(
                    '本地 Socket：${result.localAddress}:${result.localPort}',
                  ),
                  LocalizedText('往返耗时：${result.elapsed.inMilliseconds} ms'),
                  if (result.software != null)
                    LocalizedText('服务端：${result.software}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const LocalizedText(
            '这里显示 RFC 5389 映射地址。仅一次 Binding 无法可靠断言 Full Cone / Symmetric 等 NAT 类型，因此不会给出可能误导的类型名称。',
          ),
        ],
      ],
    ),
  );

  Future<void> _run() async {
    final port = int.tryParse(_port.text);
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = '端口范围应为 1～65535');
      return;
    }
    setState(() {
      _running = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await StunService().binding(
        server: _server.text,
        port: port,
      );
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}
