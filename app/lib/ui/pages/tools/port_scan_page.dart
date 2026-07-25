import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/port_scan_service.dart';
import '../../../services/network_defaults_service.dart';
import '../../../state/app_state.dart';

class PortScanPage extends StatefulWidget {
  const PortScanPage({super.key, required this.appState});
  final AppState appState;

  @override
  State<PortScanPage> createState() => _PortScanPageState();
}

class _PortScanPageState extends State<PortScanPage> {
  final _host = TextEditingController(text: '192.168.1.1');
  final _ports = TextEditingController(text: '22,53,80,443,8080');
  final _service = PortScanService();
  final _results = <PortScanResult>[];
  CancellationToken? _token;
  StreamSubscription<PortScanResult>? _subscription;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    NetworkDefaultsService().load().then((defaults) {
      if (mounted && defaults.gateway != null) _host.text = defaults.gateway!;
    });
  }

  int _total = 0;

  @override
  void dispose() {
    _token?.cancel();
    _subscription?.cancel();
    _host.dispose();
    _ports.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = _results.where((item) => item.state == PortState.open).length;
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('端口检测')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _host,
            enabled: !_running,
            decoration: const InputDecoration(label: LocalizedText('目标域名或 IP')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ports,
            enabled: !_running,
            decoration: const InputDecoration(
              label: LocalizedText('端口'),
              hint: LocalizedText('22,80,443 或 8000-8010'),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const LocalizedText('Web'),
                onPressed: _running
                    ? null
                    : () => _ports.text = '80,443,8080,8443',
              ),
              ActionChip(
                label: const LocalizedText('远程'),
                onPressed: _running
                    ? null
                    : () => _ports.text = '22,23,3389,5900',
              ),
              ActionChip(
                label: const LocalizedText('常用'),
                onPressed: _running
                    ? null
                    : () => _ports.text =
                          '21,22,25,53,80,110,143,443,445,3306,3389,5432,8080',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : _start,
                  icon: const Icon(Icons.radar),
                  label: const LocalizedText('开始检测'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _running ? _stop : null,
                child: const LocalizedText('停止'),
              ),
            ],
          ),
          if (_running)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(
                value: _total == 0 ? null : _results.length / _total,
              ),
            ),
          if (_results.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metric('已完成', '${_results.length}/$_total'),
                    _metric('开放', '$open'),
                    _metric('未开放', '${_results.length - open}'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          ..._results.map(
            (item) => Card(
              child: ListTile(
                leading: Icon(
                  item.state == PortState.open
                      ? Icons.lock_open
                      : Icons.lock_outline,
                  color: item.state == PortState.open
                      ? Colors.green
                      : Theme.of(context).colorScheme.outline,
                ),
                title: LocalizedText(
                  '${item.port} / ${_serviceName(item.port)}',
                ),
                subtitle: LocalizedText('${item.elapsed.inMilliseconds} ms'),
                trailing: LocalizedText(
                  item.state == PortState.open ? 'OPEN' : 'CLOSED',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: item.state == PortState.open ? Colors.green : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LocalizedText(
            '仅对自己拥有或已获授权的设备进行扫描。一次最多 256 个端口。',
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

  void _start() {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    List<int> ports;
    try {
      ports = _service.parsePorts(_ports.text);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText(error.message)));
      return;
    }
    _results.clear();
    _total = ports.length;
    _token = CancellationToken();
    setState(() => _running = true);
    _subscription = _service
        .scan(
          host: host,
          ports: ports,
          timeout: const Duration(milliseconds: 900),
          token: _token!,
        )
        .listen(
          (result) => setState(() => _results.add(result)),
          onDone: _finish,
        );
  }

  Future<void> _finish() async {
    if (!mounted) return;
    setState(() => _running = false);
    final openPorts = _results
        .where((item) => item.state == PortState.open)
        .map((item) => item.port)
        .toList();
    final detail = _results
        .map((item) => '${item.port} ${item.state.name.toUpperCase()}')
        .join('\n');
    await widget.appState.addHistory(
      tool: 'port_scan',
      title: '端口检测 ${_host.text}',
      summary: openPorts.isEmpty ? '未发现开放端口' : '开放：${openPorts.join(', ')}',
      detail: detail,
      success: true,
    );
  }

  void _stop() {
    _token?.cancel();
    _subscription?.cancel();
    setState(() => _running = false);
  }

  String _serviceName(int port) =>
      const {
        21: 'FTP',
        22: 'SSH',
        25: 'SMTP',
        53: 'DNS',
        80: 'HTTP',
        110: 'POP3',
        143: 'IMAP',
        443: 'HTTPS',
        445: 'SMB',
        3306: 'MySQL',
        3389: 'RDP',
        5432: 'PostgreSQL',
        5900: 'VNC',
        6379: 'Redis',
        8080: 'HTTP-alt',
      }[port] ??
      'Unknown';
}
