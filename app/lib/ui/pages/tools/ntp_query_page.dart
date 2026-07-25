import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/ntp_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class NtpQueryPage extends StatefulWidget {
  const NtpQueryPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<NtpQueryPage> createState() => _NtpQueryPageState();
}

class _NtpQueryPageState extends State<NtpQueryPage> {
  final _service = NtpService();
  final _server = TextEditingController(text: 'ntp.aliyun.com');
  final _results = <NtpResult>[];
  bool _running = false;
  int _count = 4;
  int _timeoutSeconds = 3;
  int _intervalMs = 800;
  String? _error;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _server.addListener(_saveDraft);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _service.cancel();
    if (_draftLoaded) unawaited(_drafts.save('tool.ntp', _draftValue()));
    _drafts.dispose();
    _server.dispose();
    super.dispose();
  }

  Map<String, Object?> _draftValue() => {
    'server': _server.text,
    'count': _count,
    'timeoutSeconds': _timeoutSeconds,
    'intervalMs': _intervalMs,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.ntp');
    if (!mounted) return;
    if (draft != null) {
      setState(() {
        _server.text = draft.payload['server']?.toString() ?? _server.text;
        _count = (draft.payload['count'] as num?)?.toInt() ?? _count;
        _timeoutSeconds =
            (draft.payload['timeoutSeconds'] as num?)?.toInt() ??
            _timeoutSeconds;
        _intervalMs =
            (draft.payload['intervalMs'] as num?)?.toInt() ?? _intervalMs;
      });
    }
    _draftLoaded = true;
  }

  void _saveDraft() {
    if (_draftLoaded) _drafts.scheduleSave('tool.ntp', _draftValue());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('NTP 时间查询'),
      actions: [
        if (_results.isNotEmpty)
          IconButton(
            tooltip: context.tr('复制完整报告'),
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_outlined),
          ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          TextField(
            controller: _server,
            enabled: !_running,
            decoration: const InputDecoration(
              label: LocalizedText('NTP 服务器'),
              prefixIcon: Icon(Icons.schedule_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const [
                'ntp.aliyun.com',
                'cn.pool.ntp.org',
                'time.cloudflare.com',
              ])
                ActionChip(
                  label: LocalizedText(value),
                  onPressed: _running
                      ? null
                      : () {
                          setState(() => _server.text = value);
                          _saveDraft();
                        },
                ),
            ],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const LocalizedText(
              '查询参数',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _count,
                      decoration: const InputDecoration(
                        label: LocalizedText('次数'),
                      ),
                      items: [1, 2, 4, 6, 10]
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: LocalizedText('$v'),
                            ),
                          )
                          .toList(),
                      onChanged: _running
                          ? null
                          : (v) {
                              setState(() => _count = v ?? 4);
                              _saveDraft();
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _timeoutSeconds,
                      decoration: const InputDecoration(
                        label: LocalizedText('超时'),
                      ),
                      items: [1, 2, 3, 5, 10]
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: LocalizedText('$v 秒'),
                            ),
                          )
                          .toList(),
                      onChanged: _running
                          ? null
                          : (v) {
                              setState(() => _timeoutSeconds = v ?? 3);
                              _saveDraft();
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _intervalMs,
                decoration: const InputDecoration(label: LocalizedText('查询间隔')),
                items: [250, 500, 800, 1000, 2000]
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: LocalizedText('$v ms'),
                      ),
                    )
                    .toList(),
                onChanged: _running
                    ? null
                    : (v) {
                        setState(() => _intervalMs = v ?? 800);
                        _saveDraft();
                      },
              ),
              const SizedBox(height: 10),
            ],
          ),
          const SizedBox(height: 12),
          if (_running)
            OutlinedButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const LocalizedText('停止查询'),
            )
          else
            FilledButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const LocalizedText('开始查询'),
            ),
          if (_running) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _results.length / _count),
          ],
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
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 18),
            _summary(),
            const SizedBox(height: 18),
            _chart(),
            const SizedBox(height: 18),
            _details(),
          ],
        ],
      ),
    ),
  );

  Widget _summary() {
    final offsets = _results.map((e) => e.offsetMs).toList();
    final delays = _results.map((e) => e.roundTripMs).toList();
    final averageOffset = offsets.reduce((a, b) => a + b) / offsets.length;
    final averageDelay = delays.reduce((a, b) => a + b) / delays.length;
    final sortedOffsets = [...offsets]..sort();
    final medianOffset = sortedOffsets.length.isOdd
        ? sortedOffsets[sortedOffsets.length ~/ 2]
        : (sortedOffsets[sortedOffsets.length ~/ 2 - 1] +
                  sortedOffsets[sortedOffsets.length ~/ 2]) /
              2;
    var jitter = 0.0;
    if (offsets.length > 1) {
      for (var index = 1; index < offsets.length; index++) {
        jitter += (offsets[index] - offsets[index - 1]).abs();
      }
      jitter /= offsets.length - 1;
    }
    final latest = _results.last;
    final rootDistance = latest.rootDelayMs / 2 + latest.rootDispersionMs;
    final quality = _qualityAssessment(
      latest: latest,
      medianOffset: medianOffset,
      jitter: jitter,
      averageDelay: averageDelay,
      rootDistance: rootDistance,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: LocalizedText(
                    '时间同步质量',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(label: LocalizedText('Stratum ${latest.stratum}')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metric('中位偏移', '${medianOffset.toStringAsFixed(2)} ms'),
                _metric('偏移抖动', '${jitter.toStringAsFixed(2)} ms'),
                _metric('丢失', '${_count - _results.length} / $_count'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _metric(
                  '平均偏移',
                  '${averageOffset >= 0 ? '+' : ''}${averageOffset.toStringAsFixed(2)} ms',
                ),
                _metric('平均往返', '${averageDelay.toStringAsFixed(2)} ms'),
                _metric('成功', '${_results.length} / $_count'),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              color: quality.$1 == Icons.check_circle_outline_rounded
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: Icon(quality.$1),
                title: LocalizedText(quality.$2),
                subtitle: LocalizedText(quality.$3),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              '${latest.address} · ${latest.serverTime.toLocal().toIso8601String()}',
            ),
            const SizedBox(height: 4),
            LocalizedText(
              '根距离 ${rootDistance.toStringAsFixed(2)} ms · LI ${latest.leapIndicator} · NTP v${latest.version}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _chart() {
    final absolute = _results.fold<double>(
      1,
      (value, item) =>
          value > item.offsetMs.abs() ? value : item.offsetMs.abs(),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LocalizedText(
              '时钟偏移',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 190,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (_results.length - 1).clamp(1, 20).toDouble(),
                  minY: -absolute * 1.25,
                  maxY: absolute * 1.25,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(drawVerticalLine: false),
                  titlesData: const FlTitlesData(
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < _results.length; i++)
                          FlSpot(i.toDouble(), _results[i].offsetMs),
                      ],
                      color: const Color(0xFF3578F6),
                      barWidth: 2.5,
                      isCurved: true,
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF3578F6).withValues(alpha: .08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _details() => Card(
    margin: EdgeInsets.zero,
    child: ExpansionTile(
      initiallyExpanded: true,
      title: const LocalizedText(
        '每次查询与服务器参数',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      children: [
        for (var i = 0; i < _results.length; i++)
          ListTile(
            leading: CircleAvatar(child: LocalizedText('${i + 1}')),
            title: LocalizedText(
              '偏移 ${_results[i].offsetMs.toStringAsFixed(2)} ms · RTT ${_results[i].roundTripMs.toStringAsFixed(2)} ms',
            ),
            subtitle: LocalizedText(
              'Ref ${_results[i].referenceId} · Root delay ${_results[i].rootDelayMs.toStringAsFixed(2)} ms · dispersion ${_results[i].rootDispersionMs.toStringAsFixed(2)} ms',
            ),
          ),
      ],
    ),
  );

  Future<void> _run() async {
    if (_server.text.trim().isEmpty) {
      setState(() => _error = '请输入 NTP 服务器');
      return;
    }
    setState(() {
      _running = true;
      _results.clear();
      _error = null;
    });
    for (var i = 0; i < _count && _running; i++) {
      try {
        final result = await _service.query(
          _server.text,
          timeout: Duration(seconds: _timeoutSeconds),
        );
        if (!mounted || !_running) break;
        setState(() => _results.add(result));
      } on NtpCancelled {
        break;
      } on Object catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
      if (i + 1 < _count && _running)
        await Future<void>.delayed(Duration(milliseconds: _intervalMs));
    }
    if (mounted) setState(() => _running = false);
  }

  void _stop() {
    _service.cancel();
    setState(() => _running = false);
  }

  (IconData, String, String) _qualityAssessment({
    required NtpResult latest,
    required double medianOffset,
    required double jitter,
    required double averageDelay,
    required double rootDistance,
  }) {
    if (latest.leapIndicator == 3) {
      return (
        Icons.warning_amber_rounded,
        '服务器时钟未同步',
        'Leap Indicator 为 3，不应将本次结果用于校时。',
      );
    }
    if (latest.stratum > 15 || rootDistance > 1000) {
      return (
        Icons.warning_amber_rounded,
        '时间源质量较差',
        '层级或根距离偏高，建议更换距离更近的 NTP 服务器。',
      );
    }
    if (medianOffset.abs() > 100 || jitter > 50 || averageDelay > 500) {
      return (
        Icons.info_outline_rounded,
        '链路波动影响测量',
        '偏移、抖动或往返延迟偏高，建议增加样本并交叉查询其他服务器。',
      );
    }
    return (
      Icons.check_circle_outline_rounded,
      '时间同步质量良好',
      '样本偏移与抖动较低，可继续与第二个时间源交叉验证。',
    );
  }

  Future<void> _copyReport() async {
    if (_results.isEmpty) return;
    final offsets = _results.map((item) => item.offsetMs).toList()..sort();
    final median = offsets.length.isOdd
        ? offsets[offsets.length ~/ 2]
        : (offsets[offsets.length ~/ 2 - 1] + offsets[offsets.length ~/ 2]) / 2;
    final report = <String>[
      'NTP ${_server.text.trim()}',
      'Samples: ${_results.length}/$_count',
      'Median offset: ${median.toStringAsFixed(3)} ms',
      for (var index = 0; index < _results.length; index++)
        '#${index + 1} ${_results[index].address} '
            'offset=${_results[index].offsetMs.toStringAsFixed(3)}ms '
            'rtt=${_results[index].roundTripMs.toStringAsFixed(3)}ms '
            'stratum=${_results[index].stratum} '
            'ref=${_results[index].referenceId}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('报告已复制')));
    }
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
