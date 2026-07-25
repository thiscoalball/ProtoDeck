import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../models/structured_payload.dart';
import '../../../services/network_defaults_service.dart';
import '../../../services/socket_debug_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../widgets/structured_data_viewer.dart';

class SocketDebugPage extends StatefulWidget {
  const SocketDebugPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<SocketDebugPage> createState() => _SocketDebugPageState();
}

class _SocketDebugPageState extends State<SocketDebugPage> {
  final _service = SocketDebugService.instance;
  final _host = TextEditingController();
  final _port = TextEditingController(text: '9000');
  final _bind = TextEditingController(text: '0.0.0.0');
  final _localPort = TextEditingController(text: '0');
  final _payload = TextEditingController(text: 'Hello ProtoDeck');
  final _replyHost = TextEditingController();
  final _replyPort = TextEditingController();
  final _sendInterval = TextEditingController(text: '1000');
  final _events = <SocketDebugEvent>[];
  StreamSubscription<SocketDebugEvent>? _subscription;
  SocketDebugProtocol _protocol = SocketDebugProtocol.tcp;
  SocketDebugRole _role = SocketDebugRole.client;
  bool _running = false;
  bool _busy = false;
  bool _hex = false;
  bool _appendCrLf = false;
  bool _broadcast = false;
  bool _autoSend = false;
  bool _sending = false;
  String? _selectedPeer;
  Timer? _sendTimer;
  String _status = '未启动';
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _events.addAll(_service.history);
    _running = _service.running;
    _status = _service.status;
    _protocol = _service.protocol ?? _protocol;
    _role = _service.role ?? _role;
    for (final controller in [
      _host,
      _port,
      _bind,
      _localPort,
      _payload,
      _replyHost,
      _replyPort,
      _sendInterval,
    ]) {
      controller.addListener(_saveDraft);
    }
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
    _restoreDraft();
  }

  @override
  void dispose() {
    _stopAutoSend();
    _subscription?.cancel();
    if (_draftLoaded) {
      unawaited(_drafts.save('tool.socket_debug', _draftValue()));
    }
    _drafts.dispose();
    for (final controller in [
      _host,
      _port,
      _bind,
      _localPort,
      _payload,
      _replyHost,
      _replyPort,
      _sendInterval,
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
          onPressed: _events.isEmpty
              ? null
              : () {
                  _service.clearHistory();
                  setState(_events.clear);
                },
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
              : (value) {
                  setState(() => _protocol = value.first);
                  _saveDraft();
                },
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
              : (value) {
                  setState(() => _role = value.first);
                  _saveDraft();
                },
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
                          labelText: context.tr(
                            _role == SocketDebugRole.server ? '监听端口' : '目标端口',
                          ),
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
                    if (_running) ...[
                      const SizedBox(width: 8),
                      LocalizedText('${_service.peerCount} 个连接'),
                    ],
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
        if (_protocol == SocketDebugProtocol.tcp &&
            _role == SocketDebugRole.server &&
            _running) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('peer-${_service.peers.join(',')}'),
            initialValue: _service.peers.contains(_selectedPeer)
                ? _selectedPeer
                : '',
            decoration: const InputDecoration(label: LocalizedText('发送目标')),
            items: [
              const DropdownMenuItem(
                value: '',
                child: LocalizedText('所有已连接客户端'),
              ),
              for (final peer in _service.peers)
                DropdownMenuItem(value: peer, child: Text(peer)),
            ],
            onChanged: (value) => setState(() => _selectedPeer = value),
          ),
        ],
        Wrap(
          spacing: 4,
          runSpacing: 0,
          children: [
            FilterChip(
              label: const LocalizedText('Hex'),
              selected: _hex,
              onSelected: (value) {
                setState(() => _hex = value);
                _saveDraft();
              },
            ),
            FilterChip(
              label: const LocalizedText('追加 CRLF'),
              selected: _appendCrLf,
              onSelected: _hex
                  ? null
                  : (value) {
                      setState(() => _appendCrLf = value);
                      _saveDraft();
                    },
            ),
            if (_protocol == SocketDebugProtocol.udp)
              FilterChip(
                label: const LocalizedText('广播'),
                selected: _broadcast,
                onSelected: (value) {
                  setState(() => _broadcast = value);
                  _saveDraft();
                },
              ),
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _running && !_sending ? _send : null,
                  icon: const Icon(Icons.send),
                  label: const LocalizedText('发送'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _running
                      ? (_autoSend ? _stopAutoSend : _startAutoSend)
                      : null,
                  icon: Icon(
                    _autoSend
                        ? Icons.stop_circle_outlined
                        : Icons.timer_outlined,
                  ),
                  label: LocalizedText(_autoSend ? '停止循环发送' : '循环发送'),
                ),
              ),
            ],
          ),
        ),
        if (_autoSend || _running) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _sendInterval,
            enabled: !_autoSend,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              label: LocalizedText('循环间隔（毫秒）'),
              helper: LocalizedText('最小 50 ms；停止页面任务后不会自动恢复'),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            LocalizedText(
              '收发日志',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            LocalizedText(
              '${_events.length} 条 · RX ${_formatBytes(_service.receivedBytes)} · TX ${_formatBytes(_service.sentBytes)}',
            ),
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
    _stopAutoSend();
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
    if (_sending) return;
    _sending = true;
    try {
      var text = _payload.text;
      if (!_hex && _appendCrLf) text += '\r\n';
      await _service.send(
        SocketDebugService.parsePayload(text, hex: _hex),
        host: _replyHost.text,
        port: int.tryParse(_replyPort.text),
        broadcast: _broadcast,
        peer: _selectedPeer,
      );
    } on Object catch (error) {
      _showError('$error');
      if (_autoSend) _stopAutoSend();
    } finally {
      _sending = false;
    }
  }

  void _startAutoSend() {
    final interval = int.tryParse(_sendInterval.text);
    if (interval == null || interval < 50 || interval > 86400000) {
      _showError('循环间隔必须为 50～86400000 毫秒');
      return;
    }
    _sendTimer?.cancel();
    setState(() => _autoSend = true);
    unawaited(_send());
    _sendTimer = Timer.periodic(Duration(milliseconds: interval), (_) {
      if (_running && !_sending) unawaited(_send());
    });
  }

  void _stopAutoSend() {
    _sendTimer?.cancel();
    _sendTimer = null;
    if (_autoSend && mounted) setState(() => _autoSend = false);
  }

  String _formatBytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: LocalizedText(message)));
  }

  Map<String, Object?> _draftValue() => {
    'protocol': _protocol.name,
    'role': _role.name,
    'host': _host.text,
    'port': _port.text,
    'bind': _bind.text,
    'localPort': _localPort.text,
    'payload': _payload.text,
    'replyHost': _replyHost.text,
    'replyPort': _replyPort.text,
    'hex': _hex,
    'appendCrLf': _appendCrLf,
    'broadcast': _broadcast,
    'sendInterval': _sendInterval.text,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.socket_debug');
    if (!mounted) return;
    final payload = draft?.payload;
    if (payload != null) {
      if (!_service.running) {
        _protocol = SocketDebugProtocol.values.firstWhere(
          (value) => value.name == payload['protocol'],
          orElse: () => _protocol,
        );
        _role = SocketDebugRole.values.firstWhere(
          (value) => value.name == payload['role'],
          orElse: () => _role,
        );
        _host.text = payload['host']?.toString() ?? _host.text;
        _port.text = payload['port']?.toString() ?? _port.text;
        _bind.text = payload['bind']?.toString() ?? _bind.text;
        _localPort.text = payload['localPort']?.toString() ?? _localPort.text;
      }
      _payload.text = payload['payload']?.toString() ?? _payload.text;
      _replyHost.text = payload['replyHost']?.toString() ?? _replyHost.text;
      _replyPort.text = payload['replyPort']?.toString() ?? _replyPort.text;
      _hex = payload['hex'] == true;
      _appendCrLf = payload['appendCrLf'] == true;
      _broadcast = payload['broadcast'] == true;
      _sendInterval.text =
          payload['sendInterval']?.toString() ?? _sendInterval.text;
    }
    _draftLoaded = true;
    setState(() {});
  }

  void _saveDraft() {
    if (_draftLoaded) {
      _drafts.scheduleSave('tool.socket_debug', _draftValue());
    }
  }
}
