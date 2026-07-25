import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/lan_scan_service.dart';
import '../../../services/network_defaults_service.dart';
import '../../../state/app_state.dart';
import '../remote/ssh_terminal_page.dart';
import 'http_diagnostic_page.dart';
import 'ping_page.dart';
import 'telnet_terminal_page.dart';

class LanScanPage extends StatefulWidget {
  const LanScanPage({super.key, required this.appState});
  final AppState appState;
  @override
  State<LanScanPage> createState() => _LanScanPageState();
}

class _LanScanPageState extends State<LanScanPage> {
  final _cidr = TextEditingController(text: '192.168.1.0/24');
  LanScanCancellationToken? _token;
  StreamSubscription<LanScanProgress>? _subscription;
  LanScanProgress? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    NetworkDefaultsService().load().then((defaults) {
      if (mounted && defaults.subnet != null) {
        _cidr.text = defaults.subnet!;
      }
    });
  }

  @override
  void dispose() {
    _token?.cancel();
    _subscription?.cancel();
    _cidr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('局域网扫描')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _cidr,
            enabled: progress?.running != true,
            decoration: const InputDecoration(
              label: LocalizedText('IPv4 子网（最大 /20）'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: progress?.running == true ? null : _start,
                  icon: const Icon(Icons.radar),
                  label: const LocalizedText('开始扫描'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: progress?.running == true ? _stop : null,
                child: const LocalizedText('停止'),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress.total == 0
                  ? 0
                  : progress.completed / progress.total,
            ),
            LocalizedText(
              '${progress.completed}/${progress.total} · 发现 ${progress.devices.length} 台',
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: LocalizedText(_error!),
            ),
          const SizedBox(height: 12),
          ...(progress?.devices ?? const <LanDevice>[]).map(
            (device) => Card(
              child: ListTile(
                leading: const Icon(Icons.devices),
                title: LocalizedText(device.address),
                subtitle: LocalizedText(
                  '${device.hostname ?? '未知主机'}\n开放端口：${device.openPorts.join(', ')}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => _action(value, device.address),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'ping', child: LocalizedText('Ping')),
                    PopupMenuItem(value: 'http', child: LocalizedText('HTTP')),
                    PopupMenuItem(
                      value: 'telnet',
                      child: LocalizedText('Telnet :23'),
                    ),
                    PopupMenuItem(
                      value: 'ssh',
                      child: LocalizedText('SSH :22'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _start() {
    _token = LanScanCancellationToken();
    setState(() {
      _progress = null;
      _error = null;
    });
    _subscription = LanScanService()
        .scan(_cidr.text, token: _token)
        .listen(
          (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onError: (Object error) {
            if (mounted) setState(() => _error = '$error');
          },
        );
  }

  void _stop() => _token?.cancel();

  void _action(String action, String host) {
    if (action == 'ping') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              PingPage(appState: widget.appState, initialHost: host),
        ),
      );
    } else if (action == 'http') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => HttpDiagnosticPage(
            appState: widget.appState,
            initialUrl: 'http://$host',
          ),
        ),
      );
    } else if (action == 'ssh') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              SshTerminalPage(appState: widget.appState, initialHost: host),
        ),
      );
    } else if (action == 'telnet') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => TelnetTerminalPage(initialHost: host),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText('暂不支持操作：$action $host')));
    }
  }
}
