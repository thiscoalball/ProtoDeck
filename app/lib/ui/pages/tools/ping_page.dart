import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/icmp_ping_service.dart';
import '../../../services/network_defaults_service.dart';
import '../../../services/tcp_ping_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../services/udp_ping_service.dart';
import '../../../state/app_state.dart';
import '../../widgets/related_tool_actions.dart';

enum PingMode { icmp, tcp, udpEcho, udpProbe }

class _PingPoint {
  const _PingPoint(this.sequence, this.elapsedMs, this.success, this.detail);
  final int sequence;
  final double? elapsedMs;
  final bool success;
  final String detail;
}

class PingPage extends StatefulWidget {
  const PingPage({
    super.key,
    required this.appState,
    this.initialMode = PingMode.icmp,
    this.title = 'Ping',
    this.initialHost,
  });
  final AppState appState;
  final PingMode initialMode;
  final String title;
  final String? initialHost;

  @override
  State<PingPage> createState() => _PingPageState();
}

class _PingPageState extends State<PingPage> {
  static const _draftScope = 'tool.ping';
  late final _host = TextEditingController(
    text: widget.initialHost ?? '1.1.1.1',
  );
  final _port = TextEditingController(text: '443');
  final _count = TextEditingController(text: '10');
  final _interval = TextEditingController(text: '1000');
  final _timeout = TextEditingController(text: '2000');
  final _packetSize = TextEditingController(text: '56');
  final _points = <_PingPoint>[];
  late PingMode _mode = widget.initialMode;
  String _ipVersion = 'auto';
  bool _continuous = false;
  bool _running = false;
  bool _showSettings = false;
  bool _showAdvancedStats = false;
  bool _showPackets = false;
  CancellationToken? _tcpToken;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    for (final controller in [
      _host,
      _port,
      _count,
      _interval,
      _timeout,
      _packetSize,
    ]) {
      controller.addListener(_scheduleDraft);
    }
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final restored = await _drafts.load(_draftScope);
    if (!mounted) return;
    if (restored != null) {
      final value = restored.payload;
      if (widget.initialHost == null) {
        _host.text = value['host']?.toString() ?? _host.text;
      }
      _port.text = value['port']?.toString() ?? _port.text;
      _count.text = value['count']?.toString() ?? _count.text;
      _interval.text = value['interval']?.toString() ?? _interval.text;
      _timeout.text = value['timeout']?.toString() ?? _timeout.text;
      _packetSize.text = value['packetSize']?.toString() ?? _packetSize.text;
      setState(() {
        _mode = PingMode.values.firstWhere(
          (item) => item.name == value['mode']?.toString(),
          orElse: () => _mode,
        );
        _ipVersion = value['ipVersion']?.toString() ?? _ipVersion;
        _continuous = value['continuous'] == true;
        _showSettings = value['showSettings'] == true;
        _showAdvancedStats = value['showAdvancedStats'] == true;
        _showPackets = value['showPackets'] == true;
      });
      _draftLoaded = true;
      return;
    }
    _draftLoaded = true;
    if (widget.initialHost == null) {
      NetworkDefaultsService().load().then((defaults) {
        if (mounted && defaults.gateway != null) _host.text = defaults.gateway!;
      });
    }
  }

  Map<String, Object?> _draftSnapshot() => {
    'host': _host.text,
    'port': _port.text,
    'count': _count.text,
    'interval': _interval.text,
    'timeout': _timeout.text,
    'packetSize': _packetSize.text,
    'mode': _mode.name,
    'ipVersion': _ipVersion,
    'continuous': _continuous,
    'showSettings': _showSettings,
    'showAdvancedStats': _showAdvancedStats,
    'showPackets': _showPackets,
  };

  void _scheduleDraft() {
    if (_draftLoaded) _drafts.scheduleSave(_draftScope, _draftSnapshot());
  }

  @override
  void dispose() {
    _tcpToken?.cancel();
    if (_draftLoaded) unawaited(_drafts.save(_draftScope, _draftSnapshot()));
    _drafts.dispose();
    for (final controller in [
      _host,
      _port,
      _count,
      _interval,
      _timeout,
      _packetSize,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final received = _points.where((point) => point.success).toList();
    final times = received
        .map((point) => point.elapsedMs)
        .whereType<double>()
        .toList();
    final average = times.isEmpty
        ? null
        : times.reduce((a, b) => a + b) / times.length;
    final minimum = times.isEmpty ? null : times.reduce(math.min);
    final maximum = times.isEmpty ? null : times.reduce(math.max);
    final jitter = _jitter(times);
    final p50 = _percentile(times, .50);
    final p95 = _percentile(times, .95);
    final p99 = _percentile(times, .99);
    final maxConsecutiveLoss = _maxConsecutiveLoss(_points);
    final loss = _points.isEmpty
        ? 0.0
        : (_points.length - received.length) * 100 / _points.length;
    return Scaffold(
      appBar: AppBar(title: LocalizedText(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _modeSelector(),
          const SizedBox(height: 12),
          _targetCard(),
          const SizedBox(height: 10),
          _settingsPanel(),
          const SizedBox(height: 12),
          _runControls(),
          if (_points.isNotEmpty) ...[
            const SizedBox(height: 20),
            _resultSummary(received.length, average, loss, jitter),
            const SizedBox(height: 12),
            _latencyChart(),
            const SizedBox(height: 10),
            _advancedStatistics(
              minimum: minimum,
              maximum: maximum,
              p50: p50,
              p95: p95,
              p99: p99,
              maxConsecutiveLoss: maxConsecutiveLoss,
            ),
            const SizedBox(height: 10),
            _packetList(),
            const SizedBox(height: 12),
            RelatedToolActions(
              currentToolId: 'ping',
              appState: widget.appState,
              target: _host.text,
              port:
                  _mode == PingMode.tcp ||
                      _mode == PingMode.udpEcho ||
                      _mode == PingMode.udpProbe
                  ? int.tryParse(_port.text)
                  : null,
            ),
          ],
          if (_mode == PingMode.udpProbe)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: LocalizedText(
                'UDP Probe 超时只能表示状态未知；收到目标回包或 ICMP 拒绝/不可达时才能明确判断。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeSelector() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<PingMode>(
      segments: const [
        ButtonSegment(value: PingMode.icmp, label: LocalizedText('ICMP')),
        ButtonSegment(value: PingMode.tcp, label: LocalizedText('TCP')),
        ButtonSegment(
          value: PingMode.udpEcho,
          label: LocalizedText('UDP Echo'),
        ),
        ButtonSegment(
          value: PingMode.udpProbe,
          label: LocalizedText('UDP Probe'),
        ),
      ],
      selected: {_mode},
      showSelectedIcon: false,
      onSelectionChanged: _running
          ? null
          : (values) {
              setState(() => _mode = values.first);
              _scheduleDraft();
            },
    ),
  );

  Widget _targetCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.network_ping_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: LocalizedText(
                '测试目标',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            LocalizedText(
              _modeLabel(_mode),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _host,
                enabled: !_running,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hint: LocalizedText('域名或 IP 地址'),
                  prefixIcon: Icon(Icons.language_rounded, size: 20),
                ),
              ),
            ),
            if (_mode != PingMode.icmp) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: TextField(
                  controller: _port,
                  enabled: !_running,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hint: LocalizedText('端口')),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _targetChip('阿里 DNS', '223.5.5.5'),
              const SizedBox(width: 7),
              _targetChip('百度', 'baidu.com'),
              const SizedBox(width: 7),
              _targetChip('Cloudflare', '1.1.1.1'),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _targetChip(String label, String target) => FilledButton.tonalIcon(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
    icon: const Icon(Icons.bolt_rounded, size: 16),
    label: LocalizedText(label),
    onPressed: _running ? null : () => _host.text = target,
  );

  Widget _settingsPanel() => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            setState(() => _showSettings = !_showSettings);
            _scheduleDraft();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                const LocalizedText(
                  '测试参数',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LocalizedText(
                    _settingsSummary(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _showSettings
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
              ],
            ),
          ),
        ),
        if (_showSettings) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 15),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _continuous,
                  onChanged: _running
                      ? null
                      : (value) {
                          setState(() => _continuous = value);
                          _scheduleDraft();
                        },
                  title: const LocalizedText(
                    '持续 Ping',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const LocalizedText('一直运行，直到手动停止'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _count,
                        enabled: !_running && !_continuous,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          label: LocalizedText('次数'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _interval,
                        enabled: !_running,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          label: LocalizedText('间隔 ms'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
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
                    if (_mode == PingMode.icmp ||
                        _mode == PingMode.udpEcho ||
                        _mode == PingMode.udpProbe) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _packetSize,
                          enabled: !_running,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            label: LocalizedText('数据 bytes'),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_mode == PingMode.icmp) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _ipVersion,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'auto',
                        child: LocalizedText('自动选择'),
                      ),
                      DropdownMenuItem(
                        value: 'ipv4',
                        child: LocalizedText('IPv4'),
                      ),
                      DropdownMenuItem(
                        value: 'ipv6',
                        child: LocalizedText('IPv6'),
                      ),
                    ],
                    onChanged: _running
                        ? null
                        : (value) {
                            setState(() => _ipVersion = value!);
                            _scheduleDraft();
                          },
                    decoration: const InputDecoration(
                      label: LocalizedText('协议版本'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _runControls() => Column(
    children: [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: _running
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: _running ? _stop : _run,
          icon: Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded),
          label: LocalizedText(
            _running
                ? '停止测试'
                : _continuous
                ? '开始持续 Ping'
                : '开始测试',
          ),
        ),
      ),
      if (_running)
        Padding(
          padding: const EdgeInsets.only(top: 9),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: const LinearProgressIndicator(minHeight: 4),
          ),
        ),
    ],
  );

  Widget _resultSummary(
    int received,
    double? average,
    double loss,
    double? jitter,
  ) {
    final healthy = received > 0 && loss < 25;
    final color = healthy
        ? const Color(0xFF2FA778)
        : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      _running ? '实时延迟' : '测试结果',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    LocalizedText(
                      _ms(average),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    const LocalizedText('平均延迟', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      healthy
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: color,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    LocalizedText(
                      healthy ? '连接正常' : '需要关注',
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              _summaryMetric('已接收', '$received/${_points.length}'),
              _summaryMetric('丢包率', '${loss.toStringAsFixed(1)}%'),
              _summaryMetric('抖动', _ms(jitter)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryMetric(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalizedText(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        LocalizedText(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );

  Widget _latencyChart() => Container(
    padding: const EdgeInsets.fromLTRB(14, 16, 10, 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: LocalizedText(
                '延迟趋势',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            LocalizedText(
              '最近 60 次',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 176,
          child: CustomPaint(
            size: Size.infinite,
            painter: _PingChartPainter(
              List.of(_points),
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _advancedStatistics({
    required double? minimum,
    required double? maximum,
    required double? p50,
    required double? p95,
    required double? p99,
    required int maxConsecutiveLoss,
  }) => _expandableResultCard(
    icon: Icons.insights_rounded,
    title: '详细统计',
    subtitle: '最小/最大、百分位与连续丢包',
    expanded: _showAdvancedStats,
    onTap: () {
      setState(() => _showAdvancedStats = !_showAdvancedStats);
      _scheduleDraft();
    },
    child: GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 1.55,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: [
        _metric('最小', _ms(minimum)),
        _metric('最大', _ms(maximum)),
        _metric('P50', _ms(p50)),
        _metric('P95', _ms(p95)),
        _metric('P99', _ms(p99)),
        _metric('连续丢包', '$maxConsecutiveLoss'),
      ],
    ),
  );

  Widget _packetList() => _expandableResultCard(
    icon: Icons.list_alt_rounded,
    title: '逐包详情',
    subtitle: '${_points.length} 条探测记录',
    expanded: _showPackets,
    onTap: () {
      setState(() => _showPackets = !_showPackets);
      _scheduleDraft();
    },
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.separated(
        shrinkWrap: true,
        reverse: true,
        itemCount: _points.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 40),
        itemBuilder: (context, index) {
          final point = _points[_points.length - 1 - index];
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              point.success
                  ? Icons.check_circle_outline
                  : Icons.cancel_outlined,
              color: point.success
                  ? const Color(0xFF2E9C72)
                  : Theme.of(context).colorScheme.error,
            ),
            title: LocalizedText(
              '#${point.sequence}  ${point.elapsedMs == null ? '—' : '${point.elapsedMs!.toStringAsFixed(2)} ms'}',
            ),
            subtitle: LocalizedText(point.detail),
          );
        },
      ),
    ),
  );

  Widget _expandableResultCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool expanded,
    required VoidCallback onTap,
    required Widget child,
  }) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      LocalizedText(
                        subtitle,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ],
    ),
  );

  Widget _metric(String label, String value) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LocalizedText(
            value,
            maxLines: 1,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          LocalizedText(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );

  String _modeLabel(PingMode mode) => switch (mode) {
    PingMode.icmp => 'ICMP Ping',
    PingMode.tcp => 'TCP Ping',
    PingMode.udpEcho => 'UDP Echo',
    PingMode.udpProbe => 'UDP Probe',
  };

  String _settingsSummary() {
    final count = _continuous ? '持续' : '${_count.text} 次';
    final interval = int.tryParse(_interval.text);
    final intervalLabel = interval == null
        ? '${_interval.text} ms'
        : interval % 1000 == 0
        ? '${interval ~/ 1000}s'
        : '${interval}ms';
    return '$count · $intervalLabel';
  }

  Future<void> _run() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text);
    final count = int.tryParse(_count.text);
    final interval = int.tryParse(_interval.text);
    final timeout = int.tryParse(_timeout.text);
    final size = int.tryParse(_packetSize.text);
    if (host.isEmpty ||
        (!_continuous && (count == null || count < 1 || count > 10000)) ||
        interval == null ||
        interval < 100 ||
        interval > 60000 ||
        timeout == null ||
        timeout < 100 ||
        timeout > 60000 ||
        size == null ||
        size < 0 ||
        size > 65000 ||
        (_mode != PingMode.icmp &&
            (port == null || port < 1 || port > 65535))) {
      _message('参数无效：次数 1～10000，间隔/超时 100～60000ms，数据大小 0～65000 bytes');
      return;
    }
    _tcpToken = CancellationToken();
    setState(() {
      _running = true;
      _points.clear();
    });
    var sequence = 1;
    try {
      while (_running && (_continuous || sequence <= count!)) {
        final watch = Stopwatch()..start();
        _PingPoint point;
        try {
          if (_mode == PingMode.icmp) {
            final result = await IcmpPingService().run(
              host: host,
              count: 1,
              timeoutMs: timeout,
              intervalMs: interval,
              packetSize: size,
              ipv6: _ipVersion == 'auto' ? null : _ipVersion == 'ipv6',
            );
            final sample = result.samples.first;
            point = _PingPoint(
              sequence,
              sample.elapsedMs,
              sample.success,
              sample.success
                  ? '来自 ${sample.address ?? host} · TTL ${sample.ttl ?? '—'}'
                  : sample.error ?? '超时',
            );
          } else if (_mode == PingMode.tcp) {
            final sample = await TcpPingService()
                .run(
                  host: host,
                  port: port!,
                  count: 1,
                  timeout: Duration(milliseconds: timeout),
                  token: _tcpToken!,
                )
                .first;
            point = _PingPoint(
              sequence,
              sample.elapsed.inMicroseconds / 1000,
              sample.success,
              sample.success ? 'TCP $host:$port 已连接' : sample.error ?? '连接失败',
            );
          } else {
            final payload = List.filled(size, 'N').join();
            final result = await UdpPingService().run(
              host: host,
              port: port!,
              mode: _mode == PingMode.udpEcho
                  ? UdpPingMode.echo
                  : UdpPingMode.probe,
              payload: payload,
              timeout: Duration(milliseconds: timeout),
            );
            point = _PingPoint(
              sequence,
              result.elapsed.inMicroseconds / 1000,
              result.state == UdpProbeState.reply,
              '${result.state.name} · ${result.reply ?? ''}',
            );
          }
        } on Object catch (error) {
          watch.stop();
          point = _PingPoint(sequence, null, false, '$error');
        }
        if (!_running || !mounted) break;
        setState(() => _points.add(point));
        sequence++;
        final remaining = interval - watch.elapsedMilliseconds;
        if (remaining > 0 && _running)
          await Future<void>.delayed(Duration(milliseconds: remaining));
      }
    } finally {
      if (mounted) setState(() => _running = false);
      if (_points.isNotEmpty) {
        final ok = _points.where((point) => point.success).length;
        await widget.appState.addHistory(
          tool: 'ping',
          title: '${_mode.name} Ping $host',
          summary: '$ok/${_points.length} 成功',
          detail: _points
              .map(
                (point) =>
                    '#${point.sequence} ${point.elapsedMs?.toStringAsFixed(2) ?? '—'} ms ${point.detail}',
              )
              .join('\n'),
          success: ok > 0,
        );
      }
    }
  }

  void _stop() {
    _tcpToken?.cancel();
    setState(() => _running = false);
  }

  double? _jitter(List<double> values) {
    if (values.length < 2) return null;
    var total = 0.0;
    for (var index = 1; index < values.length; index++)
      total += (values[index] - values[index - 1]).abs();
    return total / (values.length - 1);
  }

  double? _percentile(List<double> values, double percentile) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final position = (sorted.length - 1) * percentile;
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  }

  int _maxConsecutiveLoss(List<_PingPoint> points) {
    var current = 0;
    var maximum = 0;
    for (final point in points) {
      if (point.success) {
        current = 0;
      } else {
        current++;
        maximum = math.max(maximum, current);
      }
    }
    return maximum;
  }

  String _ms(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} ms';
  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: LocalizedText(value)));
}

class _PingChartPainter extends CustomPainter {
  _PingChartPainter(this.points, this.color);
  final List<_PingPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    const bottom = 22.0;
    final plot = Rect.fromLTRB(left, 5, size.width - 6, size.height - bottom);
    final values = points
        .map((point) => point.elapsedMs)
        .whereType<double>()
        .toList();
    final maximum = values.isEmpty
        ? 100.0
        : math.max(10.0, values.reduce(math.max) * 1.15);
    final grid = Paint()
      ..color = color.withValues(alpha: .12)
      ..strokeWidth = 1;
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (var row = 0; row <= 4; row++) {
      final y = plot.top + plot.height * row / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      text.text = TextSpan(
        text: '${(maximum * (4 - row) / 4).round()}',
        style: const TextStyle(fontSize: 9, color: Color(0xFF66859D)),
      );
      text.layout();
      text.paint(canvas, Offset(2, y - 5));
    }
    if (points.isEmpty) return;
    final visible = points.length > 60
        ? points.sublist(points.length - 60)
        : points;
    final path = Path();
    var started = false;
    for (var index = 0; index < visible.length; index++) {
      final value = visible[index].elapsedMs;
      if (value == null) {
        started = false;
        final x =
            plot.left + index / math.max(1, visible.length - 1) * plot.width;
        canvas.drawCircle(
          Offset(x, plot.bottom - 3),
          3.5,
          Paint()..color = const Color(0xFFD34D4D),
        );
        continue;
      }
      final x =
          plot.left + index / math.max(1, visible.length - 1) * plot.width;
      final y = plot.bottom - (value / maximum).clamp(0, 1) * plot.height;
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.7, Paint()..color = color);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PingChartPainter old) => true;
}
