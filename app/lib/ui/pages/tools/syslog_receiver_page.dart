import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../models/structured_payload.dart';
import '../../../services/native_network_service.dart';
import '../../../services/syslog_receiver_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../widgets/structured_data_viewer.dart';

class SyslogReceiverPage extends StatefulWidget {
  const SyslogReceiverPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<SyslogReceiverPage> createState() => _SyslogReceiverPageState();
}

class _SyslogReceiverPageState extends State<SyslogReceiverPage> {
  final _service = SyslogReceiverService.instance;
  final _native = NativeNetworkService();
  final _port = TextEditingController(text: '5514');
  final _search = TextEditingController();
  final _messages = <SyslogMessage>[];
  StreamSubscription<SyslogMessage>? _subscription;
  SyslogTransport _transport = SyslogTransport.both;
  int? _severity;
  bool _running = false;
  bool _paused = false;
  String? _error;
  int _received = 0;
  int _dropped = 0;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _port.addListener(_saveDraft);
    _search.addListener(_saveDraft);
    _messages.addAll(_service.history);
    _received = _service.receivedCount;
    _dropped = _service.droppedCount;
    _running = _service.running;
    if (_running) {
      _transport = _service.transport;
      _port.text = '${_service.port}';
    }
    _subscription = _service.messages.listen((message) {
      _received = _service.receivedCount;
      _dropped = _service.droppedCount;
      if (_messages.length >= 5000) {
        _messages.removeAt(0);
      }
      _messages.add(message);
      if (mounted && !_paused) setState(() {});
    });
    _restoreDraft();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_draftLoaded) {
      unawaited(_drafts.save('tool.syslog', _draftValue()));
    }
    _drafts.dispose();
    _port.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _messages.reversed
        .where((message) {
          if (_severity != null && message.severity != _severity) return false;
          if (query.isEmpty) return true;
          return '${message.remoteAddress} ${message.hostname} ${message.appName} ${message.message} ${message.facilityName} ${message.severityName}'
              .toLowerCase()
              .contains(query);
        })
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Syslog 接收器'),
        actions: [
          IconButton(
            tooltip: context.tr('导出筛选日志'),
            onPressed: _messages.isEmpty ? null : _exportJsonLines,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: context.tr('清空日志'),
            onPressed: _messages.isEmpty ? null : _clearMessages,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            Icons.receipt_long_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LocalizedText(
                                _running ? '正在接收 Syslog' : '手机作为日志服务器',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              LocalizedText(
                                _running
                                    ? '${_transportLabel(_transport)} · 0.0.0.0:${_port.text}'
                                    : '支持 UDP、TCP 与常用 Syslog 分帧',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<SyslogTransport>(
                            initialValue: _transport,
                            decoration: const InputDecoration(
                              label: LocalizedText('传输方式'),
                            ),
                            items: SyslogTransport.values
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: LocalizedText(
                                      _transportLabel(value),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _running
                                ? null
                                : (value) {
                                    setState(
                                      () => _transport =
                                          value ?? SyslogTransport.both,
                                    );
                                    _saveDraft();
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _port,
                            enabled: !_running,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              label: LocalizedText('监听端口'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_running)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  setState(() => _paused = !_paused),
                              icon: Icon(
                                _paused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                              ),
                              label: LocalizedText(_paused ? '继续刷新' : '暂停界面'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                              onPressed: _stop,
                              icon: const Icon(Icons.stop_rounded),
                              label: const LocalizedText('停止接收'),
                            ),
                          ),
                        ],
                      )
                    else
                      FilledButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const LocalizedText('启动接收器'),
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
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _stat('已接收', '$_received')),
                const SizedBox(width: 8),
                Expanded(child: _stat('TCP 客户端', '${_service.clientCount}')),
                const SizedBox(width: 8),
                Expanded(child: _stat('缓存丢弃', '$_dropped')),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hint: LocalizedText('搜索来源、主机、应用或消息'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 9,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final value = index == 0 ? null : index - 1;
                  final label = value == null
                      ? '全部级别'
                      : const [
                          '紧急',
                          '警报',
                          '严重',
                          '错误',
                          '警告',
                          '通知',
                          '信息',
                          '调试',
                        ][value];
                  return ChoiceChip(
                    label: LocalizedText(label),
                    selected: _severity == value,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() => _severity = value);
                      _saveDraft();
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            if (visible.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Center(
                    child: LocalizedText(
                      _running ? '等待路由器或服务器发送日志' : '启动后将在这里显示实时消息',
                    ),
                  ),
                ),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final message in visible.take(500))
                      ListTile(
                        leading: Container(
                          width: 10,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _severityColor(message.severity),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        title: LocalizedText(
                          message.message.isEmpty
                              ? message.raw
                              : message.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: LocalizedText(
                          '${message.severityName} · ${message.facilityName} · ${message.transport} · ${message.remoteAddress}${message.appName.isEmpty ? '' : ' · ${message.appName}'}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _showMessage(message),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalizedText(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        LocalizedText(label, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );

  Future<void> _start() async {
    final port = int.tryParse(_port.text);
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = '监听端口必须是 1～65535');
      return;
    }
    setState(() => _error = null);
    try {
      await _service.start(transport: _transport, port: port);
      await _native.startForegroundTask(
        'Syslog 接收器运行中',
        '${_transportLabel(_transport)} · 端口 $port',
      );
      if (mounted) setState(() => _running = true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _stop() async {
    await _service.stop();
    await _native.stopForegroundTask();
    if (mounted)
      setState(() {
        _running = false;
        _paused = false;
      });
  }

  void _clearMessages() {
    _service.clearHistory();
    setState(() {
      _messages.clear();
      _received = 0;
      _dropped = 0;
    });
  }

  List<SyslogMessage> _filteredMessages() {
    final query = _search.text.trim().toLowerCase();
    return _messages
        .where((message) {
          if (_severity != null && message.severity != _severity) return false;
          if (query.isEmpty) return true;
          return '${message.remoteAddress} ${message.hostname} ${message.appName} ${message.message} ${message.facilityName} ${message.severityName}'
              .toLowerCase()
              .contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _exportJsonLines() async {
    try {
      final rows = _filteredMessages();
      final output = rows
          .map(
            (message) => jsonEncode({
              'receivedAt': message.receivedAt.toUtc().toIso8601String(),
              'transport': message.transport,
              'remoteAddress': message.remoteAddress,
              'remotePort': message.remotePort,
              'standard': message.standard,
              'facility': message.facility,
              'facilityName': message.facilityName,
              'severity': message.severity,
              'severityName': message.severityName,
              'hostname': message.hostname,
              'appName': message.appName,
              'processId': message.processId,
              'messageId': message.messageId,
              'structuredData': message.structuredData,
              'message': message.message,
              'raw': message.raw,
            }),
          )
          .join('\n');
      final path = await FilePicker.platform.saveFile(
        dialogTitle: context.tr('导出 Syslog 日志'),
        fileName:
            'protodeck_syslog_${DateTime.now().millisecondsSinceEpoch}.jsonl',
        type: FileType.custom,
        allowedExtensions: const ['jsonl'],
        bytes: Uint8List.fromList(utf8.encode(output)),
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText('已保存：$path')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText('导出失败：$error')));
      }
    }
  }

  Future<void> _showMessage(
    SyslogMessage message,
  ) => showModalBottomSheet<void>(
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
              '${message.severityName} · ${message.facilityName}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            LocalizedText(
              '${message.standard} · ${message.transport} · ${message.remoteAddress}:${message.remotePort}',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StructuredDataViewer(
                payload: StructuredPayload(
                  rawText: message.message.isEmpty
                      ? message.raw
                      : message.message,
                  source: 'Syslog',
                  direction: 'RX',
                  contentType: 'text/syslog',
                  metadata: {
                    'facility': message.facilityName,
                    'severity': message.severityName,
                    'hostname': message.hostname,
                    'appName': message.appName,
                    'processId': message.processId,
                    'messageId': message.messageId,
                    'structuredData': message.structuredData,
                    'raw': message.raw,
                  },
                  timestamp: message.receivedAt,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Map<String, Object?> _draftValue() => {
    'port': _port.text,
    'transport': _transport.name,
    'search': _search.text,
    'severity': _severity,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.syslog');
    if (!mounted) return;
    final payload = draft?.payload;
    if (payload != null && !_service.running) {
      _port.text = payload['port']?.toString() ?? _port.text;
      _transport = SyslogTransport.values.firstWhere(
        (value) => value.name == payload['transport'],
        orElse: () => _transport,
      );
    }
    if (payload != null) {
      _search.text = payload['search']?.toString() ?? '';
      final severity = (payload['severity'] as num?)?.toInt();
      _severity = severity != null && severity >= 0 && severity <= 7
          ? severity
          : null;
    }
    _draftLoaded = true;
    setState(() {});
  }

  void _saveDraft() {
    if (_draftLoaded) {
      _drafts.scheduleSave('tool.syslog', _draftValue());
    }
  }
}

String _transportLabel(SyslogTransport value) => switch (value) {
  SyslogTransport.udp => 'UDP',
  SyslogTransport.tcp => 'TCP',
  SyslogTransport.both => 'UDP + TCP',
};

Color _severityColor(int severity) => switch (severity) {
  0 || 1 || 2 || 3 => const Color(0xFFE0525D),
  4 => const Color(0xFFF2A43A),
  5 => const Color(0xFF7B65D8),
  6 => const Color(0xFF3578F6),
  _ => const Color(0xFF6B7A90),
};
