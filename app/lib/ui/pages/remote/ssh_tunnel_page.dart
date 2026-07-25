import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../data/app_database.dart';
import '../../../services/native_network_service.dart';
import '../../../services/ssh_tunnel_service.dart';
import '../../../state/app_state.dart';

class SshTunnelPage extends StatefulWidget {
  const SshTunnelPage({
    super.key,
    required this.appState,
    required this.profile,
  });
  final AppState appState;
  final RemoteProfile profile;

  @override
  State<SshTunnelPage> createState() => _SshTunnelPageState();
}

class _SshTunnelPageState extends State<SshTunnelPage> {
  final _service = SshTunnelService();
  final _native = NativeNetworkService();
  final _bindHost = TextEditingController(text: '127.0.0.1');
  final _bindPort = TextEditingController(text: '8080');
  final _targetHost = TextEditingController(text: '127.0.0.1');
  final _targetPort = TextEditingController(text: '80');
  StreamSubscription<SshTunnelStats>? _subscription;
  SshTunnelMode _mode = SshTunnelMode.local;
  SshTunnelStats? _stats;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = _service.stats.listen((stats) {
      if (mounted)
        setState(() {
          _stats = stats;
          if (stats.error != null) _error = stats.error;
        });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service.dispose();
    if (_service.running) _native.stopForegroundTask();
    _bindHost.dispose();
    _bindPort.dispose();
    _targetHost.dispose();
    _targetPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _stats?.running == true;
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('SSH 隧道')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.terminal_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                title: LocalizedText(
                  widget.profile.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: LocalizedText(
                  '${widget.profile.username}@${widget.profile.host}:${widget.profile.port}',
                ),
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<SshTunnelMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: SshTunnelMode.local,
                    icon: Icon(Icons.login_rounded),
                    label: LocalizedText('Local'),
                  ),
                  ButtonSegment(
                    value: SshTunnelMode.remote,
                    icon: Icon(Icons.logout_rounded),
                    label: LocalizedText('Remote'),
                  ),
                  ButtonSegment(
                    value: SshTunnelMode.dynamic,
                    icon: Icon(Icons.hub_outlined),
                    label: LocalizedText('SOCKS5'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: running || _starting
                    ? null
                    : (value) => _changeMode(value.first),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LocalizedText(
                      _description(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _bindHost,
                            enabled: !running && !_starting,
                            decoration: InputDecoration(
                              labelText: _mode == SshTunnelMode.remote
                                  ? '远端监听地址'
                                  : '本地监听地址',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 126,
                          child: TextField(
                            controller: _bindPort,
                            enabled: !running && !_starting,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              label: LocalizedText('监听端口'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_mode != SshTunnelMode.dynamic) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _targetHost,
                              enabled: !running && !_starting,
                              decoration: const InputDecoration(
                                label: LocalizedText('目标主机'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 126,
                            child: TextField(
                              controller: _targetPort,
                              enabled: !running && !_starting,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                label: LocalizedText('目标端口'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_bindHost.text == '0.0.0.0' ||
                        _bindHost.text == '::') ...[
                      const SizedBox(height: 12),
                      Material(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: LocalizedText(
                            '当前监听全部网络接口。局域网中的其他设备可能访问这个隧道，请只在可信网络中使用。',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (running)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: _stop,
                        icon: const Icon(Icons.stop_rounded),
                        label: const LocalizedText('停止隧道'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _starting ? null : _start,
                        icon: _starting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                        label: LocalizedText(_starting ? '正在建立 SSH…' : '启动隧道'),
                      ),
                  ],
                ),
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: LocalizedText(error),
                ),
              ),
            ],
            if (_stats case final stats?) ...[
              const SizedBox(height: 18),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: LocalizedText(
                              stats.running ? '隧道运行中' : '隧道已停止',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (stats.running)
                            Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                color: Color(0xFF20B785),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        '${stats.listenHost}:${stats.listenPort}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _metric('活动连接', '${stats.activeConnections}'),
                          _metric('上传', _bytes(stats.uploadBytes)),
                          _metric('下载', _bytes(stats.downloadBytes)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _description() => switch (_mode) {
    SshTunnelMode.local => '手机监听端口，通过 SSH 访问远端网络中的目标服务。',
    SshTunnelMode.remote => 'SSH 服务器监听端口，将连接转回手机或手机所在局域网。',
    SshTunnelMode.dynamic => '在手机启动 SOCKS5 CONNECT 代理，目标连接通过 SSH 发出。',
  };

  void _changeMode(SshTunnelMode mode) => setState(() {
    _mode = mode;
    _bindHost.text = mode == SshTunnelMode.remote ? 'localhost' : '127.0.0.1';
    _bindPort.text = mode == SshTunnelMode.dynamic
        ? '1080'
        : mode == SshTunnelMode.remote
        ? '9000'
        : '8080';
  });

  Future<void> _start() async {
    final bindPort = int.tryParse(_bindPort.text);
    final targetPort = int.tryParse(_targetPort.text);
    if (bindPort == null ||
        bindPort < 0 ||
        bindPort > 65535 ||
        (_mode != SshTunnelMode.dynamic &&
            (targetPort == null || targetPort < 1 || targetPort > 65535))) {
      setState(() => _error = '请输入有效的监听端口和目标端口');
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await _service.start(
        widget.profile,
        SshTunnelConfig(
          mode: _mode,
          bindHost: _bindHost.text.trim(),
          bindPort: bindPort,
          targetHost: _targetHost.text.trim(),
          targetPort: targetPort ?? 0,
        ),
        verifyHostKey: _verify,
      );
      await _native.startForegroundTask(
        'SSH 隧道运行中',
        '${widget.profile.name} · ${_mode.name}',
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '隧道启动失败：$error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    await _service.stop();
    await _native.stopForegroundTask();
  }

  Future<bool> _verify(String algorithm, String fingerprint) async {
    final endpoint = '${widget.profile.host}:${widget.profile.port}';
    final db = widget.appState.database;
    final old = await (db.select(
      db.knownHosts,
    )..where((row) => row.endpoint.equals(endpoint))).getSingleOrNull();
    if (old != null)
      return old.algorithm == algorithm && old.fingerprint == fingerprint;
    if (!mounted) return false;
    final accepted =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const LocalizedText('首次连接主机'),
            content: SelectableText(
              '$endpoint\n$algorithm\nSHA256:$fingerprint',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const LocalizedText('拒绝'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const LocalizedText('信任并连接'),
              ),
            ],
          ),
        ) ??
        false;
    if (accepted)
      await db
          .into(db.knownHosts)
          .insert(
            KnownHostsCompanion.insert(
              endpoint: endpoint,
              algorithm: algorithm,
              fingerprint: fingerprint,
              trustedAt: DateTime.now(),
            ),
          );
    return accepted;
  }
}

Widget _metric(String label, String value) => Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LocalizedText(
        value,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      LocalizedText(label, style: const TextStyle(fontSize: 12)),
    ],
  ),
);

String _bytes(int value) {
  if (value >= 1024 * 1024)
    return '${(value / (1024 * 1024)).toStringAsFixed(2)} MB';
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '$value B';
}
