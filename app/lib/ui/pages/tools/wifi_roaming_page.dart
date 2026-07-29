import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../services/wifi_roaming_service.dart';

class WifiRoamingPage extends StatefulWidget {
  const WifiRoamingPage({super.key});

  @override
  State<WifiRoamingPage> createState() => _WifiRoamingPageState();
}

class _WifiRoamingPageState extends State<WifiRoamingPage> {
  final _session = WifiRoamingSession.instance;
  StreamSubscription<void>? _subscription;

  List<WifiRoamSample> get _samples => _session.samples;
  List<WifiRoamEvent> get _events => _session.events;
  bool get _running => _session.running;
  String? get _error => _session.error?.toString();

  @override
  void initState() {
    super.initState();
    _subscription = _session.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latest = _samples.isEmpty ? null : _samples.last;
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('Wi-Fi 漫游分析')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(19),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.cell_tower_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LocalizedText(
                                latest?.ssid ??
                                    (_running ? '等待 Wi-Fi 信息' : '观测 AP 漫游与断流'),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              LocalizedText(
                                latest?.bssid ?? '每 2 秒采样当前 BSSID、RSSI 与网关延迟',
                              ),
                            ],
                          ),
                        ),
                        if (_running)
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
                    if (latest != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _metric(
                            'RSSI',
                            latest.rssi == null ? '不可用' : '${latest.rssi} dBm',
                          ),
                          _metric(
                            '信道',
                            latest.channel == null ? '—' : '${latest.channel}',
                          ),
                          _metric(
                            '网关 RTT',
                            latest.gatewayRttMs == null
                                ? (latest.gatewayReachable ? '<1 ms' : '超时')
                                : '${latest.gatewayRttMs!.toStringAsFixed(1)} ms',
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 17),
                    if (_running)
                      OutlinedButton.icon(
                        onPressed: _stop,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const LocalizedText('停止分析'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const LocalizedText('开始漫游分析'),
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
            if (_samples.isNotEmpty) ...[
              const SizedBox(height: 18),
              _rssiChart(),
              const SizedBox(height: 18),
              _latencyChart(),
            ],
            const SizedBox(height: 18),
            const LocalizedText(
              '漫游事件',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_events.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: LocalizedText('同一 SSID 下 BSSID 切换后显示事件'),
                  ),
                ),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final event in _events.reversed) ...[
                      ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.swap_horiz_rounded),
                        ),
                        title: LocalizedText(
                          '${event.fromBssid} → ${event.toBssid}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: LocalizedText(
                          'RSSI ${event.fromRssi ?? '—'} → ${event.toRssi ?? '—'} dBm · '
                          'CH ${event.fromChannel ?? '—'} → ${event.toChannel ?? '—'} · '
                          '可观测断流 ${event.observedOutage == null ? '样本不足' : '${event.observedOutage!.inMilliseconds} ms'} · '
                          '恢复 ${event.recoveryTime?.inMilliseconds ?? 0} ms · 丢失探测 ${event.lostProbes}',
                        ),
                        trailing: LocalizedText(
                          DateFormat('HH:mm:ss').format(event.changedAt),
                        ),
                      ),
                      if (event.addressChanged ||
                          event.gatewayChanged ||
                          event.dnsChanged)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(72, 0, 16, 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: LocalizedText(
                              [
                                if (event.addressChanged) '本机地址变化',
                                if (event.gatewayChanged) '网关变化',
                                if (event.dnsChanged) 'DNS 变化',
                              ].join(' · '),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 12),
            LocalizedText(
              '“可观测断流”由网关探测计算，不等同于 802.11 握手的精确耗时。Android 未提供 BSSID 时会显示不可用，不会推测。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rssiChart() => _chartCard(
    title: 'RSSI 信号轨迹',
    minY: -100,
    maxY: 0,
    spots: [
      for (var i = 0; i < _samples.length; i++)
        if (_samples[i].rssi != null)
          FlSpot(i.toDouble(), _samples[i].rssi!.toDouble()),
    ],
    color: const Color(0xFF3578F6),
    suffix: 'dBm',
  );

  Widget _latencyChart() {
    final max = _samples
        .where((s) => s.gatewayRttMs != null)
        .fold<double>(
          10,
          (value, sample) =>
              value > sample.gatewayRttMs! ? value : sample.gatewayRttMs!,
        );
    return _chartCard(
      title: '网关延迟与断流',
      minY: 0,
      maxY: max * 1.25,
      spots: [
        for (var i = 0; i < _samples.length; i++)
          if (_samples[i].gatewayRttMs != null)
            FlSpot(i.toDouble(), _samples[i].gatewayRttMs!),
      ],
      color: const Color(0xFF16B79A),
      suffix: 'ms',
    );
  }

  Widget _chartCard({
    required String title,
    required double minY,
    required double maxY,
    required List<FlSpot> spots,
    required Color color,
    required String suffix,
  }) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalizedText(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (_samples.length - 1).clamp(1, 120).toDouble(),
                minY: minY,
                maxY: maxY,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(drawVerticalLine: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) => LocalizedText(
                        '${value.toInt()} $suffix',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    for (final event in _events)
                      if (_sampleIndex(event.changedAt) >= 0)
                        VerticalLine(
                          x: _sampleIndex(event.changedAt).toDouble(),
                          color: const Color(0xFFF2A43A),
                          strokeWidth: 1.5,
                          dashArray: [5, 4],
                        ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    color: color,
                    barWidth: 2.5,
                    isCurved: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withValues(alpha: .08),
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

  int _sampleIndex(DateTime time) =>
      _samples.indexWhere((sample) => !sample.timestamp.isBefore(time));

  void _start() {
    _session.start();
  }

  void _stop() {
    _session.stop();
  }
}

Widget _metric(String label, String value) => Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LocalizedText(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      LocalizedText(label, style: const TextStyle(fontSize: 12)),
    ],
  ),
);
