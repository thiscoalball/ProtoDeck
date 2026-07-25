import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../models/structured_payload.dart';
import '../../../services/network_defaults_service.dart';
import '../../../services/socket_debug_service.dart';
import '../../widgets/structured_data_viewer.dart';

class SocketDebugPage extends StatefulWidget {
  const SocketDebugPage({super.key});

  @override
  State<SocketDebugPage> createState() => _SocketDebugPageState();
}

class _SocketDebugPageState extends State<SocketDebugPage> {
  final _service = SocketDebugService();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '9000');
  final _bind = TextEditingController(text: '0.0.0.0');
  final _localPort = TextEditingController(text: '0');
  final _payload = TextEditingController(text: 'Hello ProtoDeck');
  final _replyHost = TextEditingController();
  final _replyPort = TextEditingController();
  final _events = <SocketDebugEvent>[];
  StreamSubscription<SocketDebugEvent>? _subscription;
  SocketDebugProtocol _protocol = SocketDebugProtocol.tcp;
  SocketDebugRole _role = SocketDebugRole.client;
  bool _running = false;
  bool _busy = false;
  bool _hex = false;
  bool _appendCrLf = false;
  bool _broadcast = false;
  String _status = '未启动';

  @override
  void initState() {
    super.initState();
    _subscription = _service.events.listen((event) {
      if (!mounted) return;
      setState(() {
        _events.insert(0, event);
        if (_events.length > 500) _events.removeLast();
        if (event.direction == 'RX' && _protocol == SocketDebugProtocol.udp) {
          final parts = event.peer.split(':');
          if (parts.length >= 2) {
            _replyPort.text = parts.removeLast();
            _replyHost.text = parts.join(':');
          }
        }
      });
    });
    NetworkDefaultsService().load().then((value) {
      if (mounted && _host.text.isEmpty) _host.text = value.gateway ?? '';
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service.dispose();
    for (final controller in [
      _host,
      _port,
      _bind,
      _localPort,
      _payload,
      _replyHost,
      _replyPort,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('TCP / UDP 调试助手'),
      actions: [
        IconButton(
          onPressed: _events.isEmpty ? null : () => setState(_events.clear),
          icon: const Icon(Icons.delete_sweep_outlined),
          tooltip: context.tr('清空日志'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<SocketDebugProtocol>(
          segments: const [
            ButtonSegment(
              value: SocketDebugProtocol.tcp,
              label: LocalizedText('TCP'),
            ),
            ButtonSegment(
              value: SocketDebugProtocol.udp,
              label: LocalizedText('UDP'),
            ),
          ],
          selected: {_protocol},
          onSelectionChanged: _running
              ? null
              : (value) => setState(() => _protocol = value.first),
        ),
        const SizedBox(height: 10),
        SegmentedButton<SocketDebugRole>(
          segments: const [
            ButtonSegment(
              value: SocketDebugRole.client,
              icon: Icon(Icons.call_made),
              label: LocalizedText('客户端'),
            ),
            ButtonSegment(
              value: SocketDebugRole.server,
              icon: Icon(Icons.dns_outlined),
              label: LocalizedText('服务端'),
            ),
          ],
          selected: {_role},
          onSelectionChanged: _running
              ? null
              : (value) => setState(() => _role = value.first),
        ),
        const SizedBox(height: 14),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                if (_role == SocketDebugRole.client)
                  TextField(
                    controller: _host,
                    enabled: !_running,
                    decoration: const InputDecoration(
                      label: LocalizedText('目标地址'),
                      prefixIcon: Icon(Icons.language),
                    ),
                  ),
                if (_role == SocketDebugRole.client) const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _bind,
                        enabled: !_running,
                        decoration: const InputDecoration(
                          label: LocalizedText('本地绑定地址'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _port,
                        enabled: !_running,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _role == SocketDebugRole.server
                              ? '监听端口'
                              : '目标端口',
                        ),
                      ),
                    ),
                  ],
                ),
                if (_role == SocketDebugRole.client) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _localPort,
                    enabled: !_running,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      label: LocalizedText('本地端口（0 为系统分配）'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : (_running ? _stop : _start),
                    icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                    label: LocalizedText(_running ? '停止' : '启动'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _running ? Icons.circle : Icons.circle_outlined,
                      size: 12,
                      color: _running ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: LocalizedText(_status)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _payload,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: context.tr(_hex ? '发送 Hex 字节' : '发送文本'),
            hintText: _hex ? '48 65 6C 6C 6F' : context.tr('输入待发送内容'),
          ),
        ),
        if (_protocol == SocketDebugProtocol.udp &&
            _role == SocketDebugRole.server) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _replyHost,
                  decoration: const InputDecoration(
                    label: LocalizedText('回复目标地址'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _replyPort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(label: LocalizedText('端口')),
                ),
              ),
            ],
          ),
        ],
        Wrap(
          spacing: 4,
          runSpacing: 0,
          children: [
            FilterChip(
              label: const LocalizedText('Hex'),
              selected: _hex,
              onSelected: (value) => setState(() => _hex = value),
            ),
            FilterChip(
              label: const LocalizedText('追加 CRLF'),
              selected: _appendCrLf,
              onSelected: _hex
                  ? null
                  : (value) => setState(() => _appendCrLf = value),
            ),
            if (_protocol == SocketDebugProtocol.udp)
              FilterChip(
                label: const LocalizedText('广播'),
                selected: _broadcast,
                onSelected: (value) => setState(() => _broadcast = value),
              ),
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: _running ? _send : null,
            icon: const Icon(Icons.send),
            label: const LocalizedText('发送'),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            LocalizedText(
              '收发日志',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            LocalizedText('${_events.length} 条'),
          ],
        ),
        const SizedBox(height: 8),
        if (_events.isEmpty)
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: LocalizedText('启动并发送数据后，日志会显示在这里')),
            ),
          )
        else
          ..._events.map(_eventTile),
      ],
    ),
  );

  Widget _eventTile(SocketDebugEvent event) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => _showPayload(event),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: switch (event.direction) {
                      'TX' => Colors.blue.withValues(alpha: .12),
                      'RX' => Colors.green.withValues(alpha: .12),
                      'ERR' => Colors.red.withValues(alpha: .12),
                      _ => Colors.grey.withValues(alpha: .12),
                    },
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: LocalizedText(event.direction),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LocalizedText(
                    event.peer,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                LocalizedText(DateFormat('HH:mm:ss.SSS').format(event.time)),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              event.text,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            if (event.bytes.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(
                '${event.bytes.length} B · ${event.hex}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Future<void> _showPayload(SocketDebugEvent event) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .86,
          minChildSize: .45,
          maxChildSize: .96,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  '${event.direction} · ${event.peer}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StructuredDataViewer(
                    payload: StructuredPayload(
                      rawText: event.text,
                      rawBytes: event.bytes,
                      source: _protocol.name.toUpperCase(),
                      direction: event.direction,
                      timestamp: event.time,
                      metadata: {
                        'peer': event.peer,
                        'size': event.bytes.length,
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _start() async {
    final port = int.tryParse(_port.text);
    final localPort = int.tryParse(_localPort.text) ?? 0;
    if (port == null) {
      _showError('请输入有效端口');
      return;
    }
    setState(() => _busy = true);
    try {
      final status = await _service.start(
        protocol: _protocol,
        role: _role,
        host: _host.text,
        port: port,
        bindAddress: _bind.text.trim().isEmpty ? '0.0.0.0' : _bind.text.trim(),
        localPort: localPort,
      );
      if (mounted)
        setState(() {
          _running = true;
          _status = status;
        });
    } on Object catch (error) {
      _showError('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    await _service.stop();
    if (mounted)
      setState(() {
        _busy = false;
        _running = false;
        _status = '已停止';
      });
  }

  Future<void> _send() async {
    try {
      var text = _payload.text;
      if (!_hex && _appendCrLf) text += '\r\n';
      await _service.send(
        SocketDebugService.parsePayload(text, hex: _hex),
        host: _replyHost.text,
        port: int.tryParse(_replyPort.text),
        broadcast: _broadcast,
      );
    } on Object catch (error) {
      _showError('$error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: LocalizedText(message)));
  }
}
