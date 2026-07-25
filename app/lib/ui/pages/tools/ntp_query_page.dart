import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/ntp_service.dart';

class NtpQueryPage extends StatefulWidget {
  const NtpQueryPage({super.key});

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

  @override
  void dispose() {
    _service.cancel();
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('NTP 时间查询')),
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
                      : () => setState(() => _server.text = value),
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
                          : (v) => setState(() => _count = v ?? 4),
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
                          : (v) => setState(() => _timeoutSeconds = v ?? 3),
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
                    : (v) => setState(() => _intervalMs = v ?? 800),
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
    final latest = _results.last;
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
            SelectableText(
              '${latest.address} · ${latest.serverTime.toLocal().toIso8601String()}',
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
