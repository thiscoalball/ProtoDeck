import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/geo_ip_service.dart';
import '../../../services/ip_tools_service.dart';
import '../../../services/native_network_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../widgets/offline_geo_map.dart';
import '../../widgets/related_tool_actions.dart';

class _TraceRow {
  _TraceRow(this.hop, {this.geo});
  final NativeTraceHop hop;
  GeoIpResult? geo;

  List<double> get successfulSamples =>
      hop.samplesMs.whereType<double>().toList();
  int get lost => hop.samplesMs.where((sample) => sample == null).length;
  double? get average => successfulSamples.isEmpty
      ? null
      : successfulSamples.reduce((a, b) => a + b) / successfulSamples.length;
  double? get minimum => successfulSamples.isEmpty
      ? null
      : successfulSamples.reduce((a, b) => a < b ? a : b);
  double? get maximum => successfulSamples.isEmpty
      ? null
      : successfulSamples.reduce((a, b) => a > b ? a : b);
}

class TraceroutePage extends StatefulWidget {
  const TraceroutePage({super.key, required this.appState, this.initialHost});
  final AppState appState;
  final String? initialHost;
  @override
  State<TraceroutePage> createState() => _TraceroutePageState();
}

class _TraceroutePageState extends State<TraceroutePage> {
  final _host = TextEditingController(text: 'baidu.com');
  final _maxHops = TextEditingController(text: '30');
  final _probes = TextEditingController(text: '3');
  final _timeout = TextEditingController(text: '1500');
  final _native = NativeNetworkService();
  late final _geo = GeoIpService(database: widget.appState.database);
  List<_TraceRow> _rows = [];
  bool _running = false;
  bool _resolveHostnames = true;
  String? _error;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    for (final controller in [_host, _maxHops, _probes, _timeout]) {
      controller.addListener(_saveDraft);
    }
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.traceroute');
    if (!mounted) return;
    if (draft != null) {
      _host.text = draft.payload['host']?.toString() ?? _host.text;
      _maxHops.text = draft.payload['maxHops']?.toString() ?? _maxHops.text;
      _probes.text = draft.payload['probes']?.toString() ?? _probes.text;
      _timeout.text = draft.payload['timeout']?.toString() ?? _timeout.text;
      setState(() {
        _resolveHostnames = draft.payload['resolveHostnames'] != false;
      });
    }
    final initialHost = widget.initialHost?.trim();
    if (initialHost != null && initialHost.isNotEmpty) _host.text = initialHost;
    _draftLoaded = true;
  }

  Map<String, Object?> _draftValue() => {
    'host': _host.text,
    'maxHops': _maxHops.text,
    'probes': _probes.text,
    'timeout': _timeout.text,
    'resolveHostnames': _resolveHostnames,
  };

  void _saveDraft() {
    if (_draftLoaded) {
      _drafts.scheduleSave('tool.traceroute', _draftValue());
    }
  }

  @override
  void dispose() {
    if (_draftLoaded) {
      unawaited(_drafts.save('tool.traceroute', _draftValue()));
    }
    _drafts.dispose();
    _host.dispose();
    _maxHops.dispose();
    _probes.dispose();
    _timeout.dispose();
    _geo.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points =
        _rows
            .where((r) => r.geo?.latitude != null && r.geo?.longitude != null)
            .map(
              (r) => GeoMapPoint(
                latitude: r.geo!.latitude!,
                longitude: r.geo!.longitude!,
                label: r.geo!.city.isEmpty ? r.geo!.country : r.geo!.city,
                order: r.hop.hop,
              ),
            )
            .toList()
          ..sort((a, b) => (a.order ?? 0).compareTo(b.order ?? 0));
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('路由追踪')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _host,
            enabled: !_running,
            decoration: const InputDecoration(label: LocalizedText('域名或 IP')),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const LocalizedText('ICMP 探针参数'),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _maxHops,
                      enabled: !_running,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        label: LocalizedText('最大跳数'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _probes,
                      enabled: !_running,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        label: LocalizedText('每跳探针'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _timeout,
                      enabled: !_running,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        label: LocalizedText('超时 ms'),
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _resolveHostnames,
                onChanged: _running
                    ? null
                    : (value) {
                        setState(() => _resolveHostnames = value);
                        _saveDraft();
                      },
                title: const LocalizedText('反向解析主机名'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: const Icon(Icons.alt_route),
                  label: const LocalizedText('开始追踪'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _running ? _stop : null,
                icon: const Icon(Icons.stop),
                label: const LocalizedText('停止'),
              ),
            ],
          ),
          if (_running) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: LocalizedText(_error!),
            ),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            _traceSummary(),
          ],
          if (points.isNotEmpty) ...[
            const SizedBox(height: 12),
            OfflineGeoMap(points: points, connectPoints: true),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LocalizedText(
                '地图按 hop 编号依次连接已获取坐标的跳点；未知位置不会参与连线。',
                style: TextStyle(fontSize: 11, color: Color(0xFF66859D)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ..._rows.map(_hopCard),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            RelatedToolActions(
              currentToolId: 'traceroute',
              appState: widget.appState,
              target: _host.text,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _run() async {
    final maxHops = int.tryParse(_maxHops.text);
    final probes = int.tryParse(_probes.text);
    final timeout = int.tryParse(_timeout.text);
    if (_host.text.trim().isEmpty ||
        maxHops == null ||
        maxHops < 1 ||
        maxHops > 64 ||
        probes == null ||
        probes < 1 ||
        probes > 5 ||
        timeout == null ||
        timeout < 500 ||
        timeout > 10000) {
      setState(() => _error = '参数范围：跳数 1～64，探针 1～5，超时 500～10000ms');
      return;
    }
    setState(() {
      _running = true;
      _rows = [];
      _error = null;
    });
    try {
      final hops = await _native.runTraceroute(
        host: _host.text.trim(),
        maxHops: maxHops,
        probes: probes,
        timeoutMs: timeout,
        resolveHostnames: _resolveHostnames,
      );
      if (!mounted) return;
      setState(() {
        _rows = hops.map(_TraceRow.new).toList()
          ..sort((a, b) => a.hop.hop.compareTo(b.hop.hop));
      });
      await _enrichGeoLocations();
      await widget.appState.addHistory(
        tool: 'traceroute',
        title: 'Traceroute ${_host.text}',
        summary: '${hops.length} 跳',
        detail: _rows
            .map(
              (r) =>
                  '${r.hop.hop} ${r.hop.address ?? '*'} ${r.hop.elapsedMs} ms',
            )
            .join('\n'),
        success: hops.isNotEmpty,
      );
    } on Object catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _stop() async {
    await _native.cancelTraceroute();
  }

  Future<void> _enrichGeoLocations() async {
    var next = 0;
    Future<void> worker() async {
      while (mounted) {
        final index = next++;
        if (index >= _rows.length) return;
        final row = _rows[index];
        final address = row.hop.address;
        if (address == null) continue;
        try {
          if (!IpToolsService().classify(address).isPublic) continue;
          final geo = await _geo.lookup(address);
          if (!mounted) return;
          setState(() => row.geo = geo);
        } on Object {
          // A missing GeoIP result must not hide or fail the actual trace hop.
        }
      }
    }

    await Future.wait(List.generate(5, (_) => worker()));
  }

  Widget _traceSummary() {
    final samples = _rows.expand((row) => row.successfulSamples).toList();
    final sent = _rows.fold<int>(
      0,
      (sum, row) => sum + row.hop.samplesMs.length,
    );
    final lost = _rows.fold<int>(0, (sum, row) => sum + row.lost);
    final reached = _rows.any((row) => row.hop.reached);
    final average = samples.isEmpty
        ? null
        : samples.reduce((a, b) => a + b) / samples.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            _summaryMetric('跳数', '${_rows.length}'),
            _summaryMetric('目标', reached ? '已到达' : '未确认到达'),
            _summaryMetric(
              '探针丢失',
              sent == 0
                  ? '—'
                  : '$lost/$sent (${(lost / sent * 100).toStringAsFixed(1)}%)',
            ),
            _summaryMetric(
              '全程平均',
              average == null ? '—' : '${average.toStringAsFixed(1)} ms',
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryMetric(String label, String value) => SizedBox(
    width: 126,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalizedText(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF66859D)),
        ),
        const SizedBox(height: 2),
        LocalizedText(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _hopCard(_TraceRow row) {
    final location = row.geo == null
        ? '私网或位置未知'
        : '${row.geo!.country} ${row.geo!.region} ${row.geo!.city}'.trim();
    final statistics = row.average == null
        ? '全部超时'
        : 'min ${row.minimum!.toStringAsFixed(1)} · '
              'avg ${row.average!.toStringAsFixed(1)} · '
              'max ${row.maximum!.toStringAsFixed(1)} ms · '
              '丢失 ${row.lost}/${row.hop.samplesMs.length}';
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(child: Text('${row.hop.hop}')),
        title: SelectableText(
          row.hop.timeout
              ? '*  *  *'
              : [
                  row.hop.hostname,
                  row.hop.address,
                ].whereType<String>().join('  '),
        ),
        subtitle: LocalizedText(
          '${row.hop.samplesMs.map((sample) => sample == null ? '*' : '${sample.toStringAsFixed(1)} ms').join('  ')}\n'
          '$statistics · $location',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  row.hop.raw.isEmpty ? '暂无原始响应' : row.hop.raw,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: context.tr('复制原始响应'),
                onPressed: row.hop.raw.isEmpty
                    ? null
                    : () => Clipboard.setData(ClipboardData(text: row.hop.raw)),
                icon: const Icon(Icons.copy_all_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
