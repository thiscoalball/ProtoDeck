import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/tcp_ping_service.dart';
import '../../../state/app_state.dart';

class TcpPingPage extends StatefulWidget {
  const TcpPingPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<TcpPingPage> createState() => _TcpPingPageState();
}

class _TcpPingPageState extends State<TcpPingPage> {
  final _host = TextEditingController(text: 'www.baidu.com');
  final _port = TextEditingController(text: '443');
  final _samples = <PingSample>[];
  CancellationToken? _token;
  StreamSubscription<PingSample>? _subscription;
  bool _running = false;

  @override
  void dispose() {
    _token?.cancel();
    _subscription?.cancel();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final success = _samples.where((item) => item.success).toList();
    final average = success.isEmpty
        ? 0
        : success
                  .map((item) => item.elapsed.inMilliseconds)
                  .reduce((a, b) => a + b) /
              success.length;
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('TCP Ping')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _host,
                  enabled: !_running,
                  decoration: const InputDecoration(
                    label: LocalizedText('域名或 IP'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _port,
                  enabled: !_running,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(label: LocalizedText('端口')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: const Icon(Icons.play_arrow),
                  label: const LocalizedText('测试 4 次'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _running ? _stop : null,
                child: const LocalizedText('停止'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_samples.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metric('成功', '${success.length}/${_samples.length}'),
                    _metric('平均', '${average.toStringAsFixed(1)} ms'),
                    _metric('失败', '${_samples.length - success.length}'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          ..._samples.map(
            (item) => Card(
              child: ListTile(
                leading: Icon(
                  item.success ? Icons.check_circle : Icons.cancel,
                  color: item.success
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
                title: LocalizedText(
                  '#${item.sequence}  ${item.success ? '${item.elapsed.inMilliseconds} ms' : '失败'}',
                ),
                subtitle: item.error == null
                    ? null
                    : LocalizedText(item.error!),
              ),
            ),
          ),
          if (_running)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
          const SizedBox(height: 12),
          LocalizedText(
            'TCP Ping 测量建立 TCP 连接的耗时，不等同于 ICMP Ping。它适合目标禁用 ICMP 时快速检查服务连通性。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
    children: [
      LocalizedText(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      LocalizedText(label),
    ],
  );

  void _run() {
    final port = int.tryParse(_port.text);
    if (_host.text.trim().isEmpty || port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('请输入有效目标和端口')));
      return;
    }
    _samples.clear();
    _token = CancellationToken();
    setState(() => _running = true);
    final stream = TcpPingService().run(
      host: _host.text.trim(),
      port: port,
      count: 4,
      timeout: const Duration(seconds: 3),
      token: _token!,
    );
    _subscription = stream.listen(
      (sample) => setState(() => _samples.add(sample)),
      onDone: _finish,
    );
  }

  Future<void> _finish() async {
    if (!mounted) return;
    setState(() => _running = false);
    if (_samples.isEmpty) return;
    final ok = _samples.where((item) => item.success).length;
    final detail = _samples
        .map(
          (item) =>
              '#${item.sequence} ${item.success ? '${item.elapsed.inMilliseconds} ms' : item.error}',
        )
        .join('\n');
    await widget.appState.addHistory(
      tool: 'tcp_ping',
      title: 'TCP Ping ${_host.text}:${_port.text}',
      summary: '$ok/${_samples.length} 成功',
      detail: detail,
      success: ok > 0,
    );
  }

  void _stop() {
    _token?.cancel();
    _subscription?.cancel();
    setState(() => _running = false);
  }
}
