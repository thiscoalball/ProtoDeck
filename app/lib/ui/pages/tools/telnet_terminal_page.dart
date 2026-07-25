import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:xterm/xterm.dart';

import '../../../services/network_defaults_service.dart';
import '../../../services/telnet_service.dart';

class TelnetTerminalPage extends StatefulWidget {
  const TelnetTerminalPage({super.key, this.initialHost});

  final String? initialHost;

  @override
  State<TelnetTerminalPage> createState() => _TelnetTerminalPageState();
}

class _TelnetTerminalPageState extends State<TelnetTerminalPage> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '23');
  final _terminal = Terminal(maxLines: 10000);
  TelnetConnection? _connection;
  StreamSubscription<String>? _outputSubscription;
  bool _connecting = false;
  bool _connected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialHost?.trim();
    if (initial?.isNotEmpty == true) {
      _host.text = initial!;
    } else {
      NetworkDefaultsService().load().then((defaults) {
        if (mounted && _host.text.isEmpty && defaults.gateway != null) {
          _host.text = defaults.gateway!;
        }
      });
    }
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    _connection?.close();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: LocalizedText(
        _connected ? '${_host.text}:${_port.text}' : 'Telnet 终端',
      ),
      actions: [
        if (_connected)
          IconButton(
            onPressed: _disconnect,
            icon: const Icon(Icons.link_off),
            tooltip: context.tr('断开'),
          ),
      ],
    ),
    body: _connected ? _terminalBody() : _connectionForm(),
  );

  Widget _connectionForm() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const LocalizedText('建立真实 Telnet 会话，支持终端类型、回显、窗口尺寸等基础协议协商。'),
      const SizedBox(height: 14),
      TextField(
        controller: _host,
        enabled: !_connecting,
        autocorrect: false,
        decoration: const InputDecoration(label: LocalizedText('主机')),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _port,
        enabled: !_connecting,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(label: LocalizedText('端口')),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _connecting ? null : _connect,
        icon: const Icon(Icons.login),
        label: LocalizedText(_connecting ? '连接中…' : '连接'),
      ),
      if (_connecting) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: LocalizedText(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 16),
      const LocalizedText('注意：Telnet 不加密用户名、密码和内容，仅建议用于可信局域网中的旧设备。'),
    ],
  );

  Widget _terminalBody() => Column(
    children: [
      Expanded(child: TerminalView(_terminal)),
      SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              _key('Esc', '\x1b'),
              _key('Tab', '\t'),
              _key('Ctrl+C', '\x03'),
              _key('Ctrl+D', '\x04'),
              _key('↑', '\x1b[A'),
              _key('↓', '\x1b[B'),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _key(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: OutlinedButton(
      onPressed: () => _connection?.sendText(value),
      child: LocalizedText(label),
    ),
  );

  Future<void> _connect() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text);
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      setState(() => _error = '请输入有效主机和端口');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final connection = await TelnetConnection.connect(host, port);
      _connection = connection;
      _terminal.onOutput = connection.sendText;
      _terminal.onResize = (width, height, _, _) =>
          connection.resize(width, height);
      _outputSubscription = connection.output.listen(
        _terminal.write,
        onDone: () {
          if (mounted) setState(() => _connected = false);
        },
      );
      if (mounted) {
        setState(() => _connected = true);
        _terminal.write('[已连接 $host:$port]\r\n');
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '连接失败：$error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    await _outputSubscription?.cancel();
    _outputSubscription = null;
    await _connection?.close();
    _connection = null;
    if (mounted) setState(() => _connected = false);
  }
}
