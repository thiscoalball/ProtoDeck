import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/stun_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class StunPage extends StatefulWidget {
  const StunPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<StunPage> createState() => _StunPageState();
}

class _StunPageState extends State<StunPage> {
  final _service = StunService();
  final _server = TextEditingController(text: 'stun.miwifi.com');
  final _port = TextEditingController(text: '3478');
  bool _running = false;
  StunBindingResult? _result;
  final _samples = <StunBindingResult>[];
  String? _error;
  bool _stabilityTest = false;
  int _sampleCount = 3;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _server.addListener(_saveDraft);
    _port.addListener(_saveDraft);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _service.cancel();
    if (_draftLoaded) unawaited(_drafts.save('tool.stun', _draftValue()));
    _drafts.dispose();
    _server.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('STUN 映射检测'),
      actions: [
        if (_result != null)
          IconButton(
            tooltip: context.tr('复制完整报告'),
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_outlined),
          ),
      ],
    ),
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
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.swap_horiz_rounded),
              label: LocalizedText('单次映射'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.repeat_rounded),
              label: LocalizedText('映射稳定性'),
            ),
          ],
          selected: {_stabilityTest},
          onSelectionChanged: _running
              ? null
              : (values) {
                  setState(() => _stabilityTest = values.first);
                  _saveDraft();
                },
        ),
        if (_stabilityTest) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _sampleCount,
            decoration: const InputDecoration(label: LocalizedText('探测次数')),
            items: const [3, 5, 8]
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(context.l10n.toolPages.timesCount(value)),
                  ),
                )
                .toList(),
            onChanged: _running
                ? null
                : (value) {
                    setState(() => _sampleCount = value ?? 3);
                    _saveDraft();
                  },
          ),
        ],
        const SizedBox(height: 14),
        if (_running)
          OutlinedButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const LocalizedText('停止探测'),
          )
        else
          FilledButton.icon(
            onPressed: _run,
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
                  if (_samples.length > 1) ...[
                    const Divider(height: 24),
                    _stabilitySummary(),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const LocalizedText(
            '这里显示 RFC 5389 映射地址。仅一次 Binding 无法可靠断言 Full Cone / Symmetric 等 NAT 类型，因此不会给出可能误导的类型名称。',
          ),
          if (_samples.length > 1)
            Card(
              child: ExpansionTile(
                title: const LocalizedText('每次映射结果'),
                children: [
                  for (var index = 0; index < _samples.length; index++)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: SelectableText(
                        '${_samples[index].mappedAddress}:'
                        '${_samples[index].mappedPort}',
                      ),
                      subtitle: Text(
                        '${_samples[index].elapsed.inMilliseconds} ms · '
                        '${_samples[index].localAddress}:'
                        '${_samples[index].localPort}',
                      ),
                    ),
                ],
              ),
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
      _samples.clear();
      _error = null;
    });
    try {
      final count = _stabilityTest ? _sampleCount : 1;
      for (var index = 0; index < count && _running; index++) {
        final result = await _service.binding(server: _server.text, port: port);
        if (!mounted) return;
        setState(() {
          _samples.add(result);
          _result = result;
        });
        if (index + 1 < count) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    } on StunCancelled {
      // User cancellation is an expected terminal state.
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _stop() {
    _service.cancel();
    setState(() => _running = false);
  }

  Future<void> _copyReport() async {
    if (_samples.isEmpty) return;
    final mappings = _samples
        .map((item) => '${item.mappedAddress}:${item.mappedPort}')
        .toSet();
    final report = <String>[
      'STUN ${_server.text.trim()}:${_port.text.trim()}',
      'Samples: ${_samples.length}',
      'Stable mapping: ${mappings.length == 1}',
      for (var index = 0; index < _samples.length; index++)
        '#${index + 1} local=${_samples[index].localAddress}:${_samples[index].localPort} '
            'mapped=${_samples[index].mappedAddress}:${_samples[index].mappedPort} '
            'rtt=${_samples[index].elapsed.inMilliseconds}ms '
            'server=${_samples[index].serverAddress}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('报告已复制')));
    }
  }

  Widget _stabilitySummary() {
    final mappings = _samples
        .map((item) => '${item.mappedAddress}:${item.mappedPort}')
        .toSet();
    final averageRtt =
        _samples
            .map((item) => item.elapsed.inMicroseconds)
            .reduce((a, b) => a + b) /
        _samples.length /
        1000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalizedText(
          mappings.length == 1 ? '本轮映射保持一致' : '本轮映射发生变化',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.toolPages.stunStabilitySummary(
            samples: _samples.length,
            mappings: mappings.length,
            averageRtt: averageRtt.toStringAsFixed(1),
          ),
        ),
      ],
    );
  }

  Map<String, Object?> _draftValue() => {
    'server': _server.text,
    'port': _port.text,
    'stabilityTest': _stabilityTest,
    'sampleCount': _sampleCount,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.stun');
    if (!mounted) return;
    if (draft != null) {
      setState(() {
        _server.text = draft.payload['server']?.toString() ?? _server.text;
        _port.text = draft.payload['port']?.toString() ?? _port.text;
        _stabilityTest = draft.payload['stabilityTest'] == true;
        _sampleCount =
            (draft.payload['sampleCount'] as num?)?.toInt() ?? _sampleCount;
      });
    }
    _draftLoaded = true;
  }

  void _saveDraft() {
    if (_draftLoaded) _drafts.scheduleSave('tool.stun', _draftValue());
  }
}
