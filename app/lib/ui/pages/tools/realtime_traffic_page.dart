import 'dart:async';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/geo_ip_service.dart';
import '../../../services/native_network_service.dart';
import '../../../services/network_intelligence_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class RealtimeTrafficPage extends StatefulWidget {
  const RealtimeTrafficPage({super.key, required this.appState});
  final AppState appState;

  @override
  State<RealtimeTrafficPage> createState() => _RealtimeTrafficPageState();
}

class _RealtimeTrafficPageState extends State<RealtimeTrafficPage> {
  final _native = NativeNetworkService();
  final _filter = TextEditingController();
  Timer? _timer;
  TrafficSnapshot? _previous;
  TrafficSnapshot? _current;
  final _samples = <TrafficRateSample>[];
  bool _running = false;
  bool _sampling = false;
  String? _error;
  int _sessionRx = 0;
  int _sessionTx = 0;
  bool _usageAccess = false;
  bool _appLoading = false;
  List<AppTrafficUsage> _appTraffic = const [];
  late final ToolDraftRepository _drafts = ToolDraftRepository(
    widget.appState.database,
  );
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _filter.addListener(_saveDraft);
    unawaited(_restoreDraft());
    _refreshAppTraffic();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_running) _native.stopForegroundTask();
    if (_draftLoaded) {
      unawaited(_drafts.save('tool.traffic_monitor', {'filter': _filter.text}));
    }
    _drafts.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.traffic_monitor');
    if (!mounted) return;
    _filter.text = draft?.payload['filter']?.toString() ?? '';
    _draftLoaded = true;
  }

  void _saveDraft() {
    if (_draftLoaded) {
      _drafts.scheduleSave('tool.traffic_monitor', {'filter': _filter.text});
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final latest = _samples.isEmpty ? null : _samples.last;
    final visibleConnections =
        current?.connections
            .where((connection) => _matches(connection, _filter.text))
            .toList(growable: false) ??
        const <TrafficConnection>[];
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('实时流量监视')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            _statusCard(latest),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline_rounded),
                  title: const LocalizedText('采样失败'),
                  subtitle: LocalizedText(error),
                ),
              ),
            ],
            if (_samples.isNotEmpty) ...[
              const SizedBox(height: 18),
              _speedChart(),
              const SizedBox(height: 18),
              _distribution(visibleConnections),
              const SizedBox(height: 18),
              _applicationTraffic(),
            ],
            const SizedBox(height: 18),
            _connectionSection(current, visibleConnections),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(TrafficRateSample? latest) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.monitor_heart_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      _running ? '正在监视设备流量' : '实时流量尚未启动',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    LocalizedText(
                      _running ? '每秒采样 · 当前会话不写入历史' : '查看上下行速率、活跃连接和协议分布',
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
          const SizedBox(height: 20),
          Row(
            children: [
              _rateMetric(
                Icons.arrow_downward_rounded,
                '下载',
                latest?.downloadBytesPerSecond ?? 0,
                const Color(0xFF3578F6),
              ),
              const SizedBox(width: 10),
              _rateMetric(
                Icons.arrow_upward_rounded,
                '上传',
                latest?.uploadBytesPerSecond ?? 0,
                const Color(0xFF16B79A),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: LocalizedText('会话下载 ${_bytes(_sessionRx)}')),
              Expanded(child: LocalizedText('会话上传 ${_bytes(_sessionTx)}')),
              LocalizedText('${latest?.activeConnections ?? 0} 个连接'),
            ],
          ),
          const SizedBox(height: 18),
          if (_running)
            OutlinedButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const LocalizedText('停止监视'),
            )
          else
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const LocalizedText('开始实时监视'),
            ),
        ],
      ),
    ),
  );

  Widget _rateMetric(IconData icon, String label, double value, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(label, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 2),
                    LocalizedText(
                      '${_rate(value)}/s',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _speedChart() {
    final maxValue = _samples.fold<double>(
      1,
      (value, sample) => [
        value,
        sample.downloadBytesPerSecond,
        sample.uploadBytesPerSecond,
      ].reduce((a, b) => a > b ? a : b),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: LocalizedText(
                    '实时速率',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                _legend(const Color(0xFF3578F6), '下载'),
                const SizedBox(width: 12),
                _legend(const Color(0xFF16B79A), '上传'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 210,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (_samples.length - 1).clamp(1, 90).toDouble(),
                  minY: 0,
                  maxY: maxValue * 1.2,
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
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
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) => LocalizedText(
                          _rate(value),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                  lineBarsData: [
                    _line(
                      (sample) => sample.downloadBytesPerSecond,
                      const Color(0xFF3578F6),
                    ),
                    _line(
                      (sample) => sample.uploadBytesPerSecond,
                      const Color(0xFF16B79A),
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

  LineChartBarData _line(
    double Function(TrafficRateSample) value,
    Color color,
  ) => LineChartBarData(
    spots: [
      for (var i = 0; i < _samples.length; i++)
        FlSpot(i.toDouble(), value(_samples[i])),
    ],
    color: color,
    barWidth: 2.5,
    isCurved: true,
    dotData: const FlDotData(show: false),
    belowBarData: BarAreaData(show: true, color: color.withValues(alpha: .08)),
  );

  Widget _distribution(List<TrafficConnection> connections) {
    final counts = <String, int>{};
    for (final connection in connections) {
      final key = connection.applicationProtocol == 'Unknown'
          ? connection.protocol
          : connection.applicationProtocol;
      counts.update(key, (value) => value + 1, ifAbsent: () => 1);
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    const colors = [
      Color(0xFF3578F6),
      Color(0xFF42B6E9),
      Color(0xFF16B79A),
      Color(0xFFF2A43A),
      Color(0xFF7B65D8),
      Color(0xFFE1638D),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LocalizedText(
              '活跃连接协议分布',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            LocalizedText(
              '按当前系统可见连接数量统计，不代表逐协议流量字节。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: LocalizedText('当前没有可见连接')),
              )
            else ...[
              SizedBox(
                height: 170,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 44,
                    sectionsSpace: 2,
                    sections: [
                      for (var i = 0; i < entries.length && i < 6; i++)
                        PieChartSectionData(
                          color: colors[i % colors.length],
                          value: entries[i].value.toDouble(),
                          radius: 31,
                          title: '${entries[i].value}',
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < entries.length && i < 8; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: LocalizedText(entries[i].key)),
                      SizedBox(
                        width: 120,
                        child: LinearProgressIndicator(
                          value: entries[i].value / entries.first.value,
                          color: colors[i % colors.length],
                          backgroundColor: colors[i % colors.length].withValues(
                            alpha: .1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      LocalizedText('${entries[i].value}'),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _applicationTraffic() => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: LocalizedText(
                  '应用流量统计',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: _appLoading ? null : _refreshAppTraffic,
                tooltip: context.tr('刷新应用流量'),
                icon: _appLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 3),
          LocalizedText(
            Platform.isWindows || Platform.isLinux
                ? '${Platform.operatingSystem} 普通模式展示真实接口速率，并将活动 TCP/UDP 端点关联到可见进程。'
                : 'Android 系统最近一小时统计，可能有入账延迟；不等同于 VPN 逐连接实时字节。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (Platform.isWindows || Platform.isLinux) ...[
            const SizedBox(height: 14),
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: LocalizedText(
                  '当前是“连接归属”模式：连接数是真实值，但不会把接口总字节推测到每个进程。精确应用字节数需要单独启用增强监控。',
                ),
              ),
            ),
          ],
          if (!(Platform.isWindows || Platform.isLinux) && !_usageAccess) ...[
            const SizedBox(height: 14),
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: LocalizedText(
                  '需要在系统设置中授予“使用情况访问”，否则 Android 不允许读取其他应用的流量汇总。',
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () async {
                await _native.openUsageStatsSettings();
              },
              icon: const Icon(Icons.settings_outlined),
              label: const LocalizedText('打开授权设置'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _refreshAppTraffic,
              icon: const Icon(Icons.verified_user_outlined),
              label: const LocalizedText('已授权，重新检测'),
            ),
          ] else if (_appTraffic.isEmpty) ...[
            const SizedBox(height: 18),
            const Center(child: LocalizedText('最近一小时没有可用的应用流量记录')),
          ] else ...[
            const SizedBox(height: 14),
            for (final item in _appTraffic.take(20))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          backgroundImage:
                              item.iconBytes == null || item.iconBytes!.isEmpty
                              ? null
                              : MemoryImage(item.iconBytes!),
                          child:
                              item.iconBytes == null || item.iconBytes!.isEmpty
                              ? LocalizedText(
                                  item.label.isEmpty
                                      ? '?'
                                      : item.label.characters.first,
                                  style: const TextStyle(fontSize: 11),
                                )
                              : null,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LocalizedText(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (item.packageName != null ||
                                  item.executablePath != null)
                                LocalizedText(
                                  item.packageName ?? item.executablePath!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        LocalizedText(
                          Platform.isWindows || Platform.isLinux
                              ? '${item.connectionCount} 个连接'
                              : '↓${_bytes(item.rxBytes)}  ↑${_bytes(item.txBytes)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    LinearProgressIndicator(
                      value: (Platform.isWindows || Platform.isLinux
                          ? item.connectionCount /
                                _appTraffic.first.connectionCount.clamp(
                                  1,
                                  1 << 30,
                                )
                          : item.totalBytes /
                                _appTraffic.first.totalBytes.clamp(1, 1 << 60)),
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    ),
  );

  Widget _connectionSection(
    TrafficSnapshot? current,
    List<TrafficConnection> connections,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LocalizedText(
        '连接与流向',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _filter,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.filter_alt_outlined),
          label: LocalizedText('BPF 风格过滤'),
          hint: LocalizedText('tcp、udp、port 443、host 1.1.1.1、ip6'),
        ),
      ),
      const SizedBox(height: 10),
      if (current?.connectionVisibility == 'restricted')
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: LocalizedText('${Platform.operatingSystem} 限制了全局连接明细'),
            subtitle: const LocalizedText('上下行曲线仍是系统真实计数；受限项目会保持不可用状态，不会推测。'),
          ),
        )
      else if (connections.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Center(
              child: LocalizedText(
                _running ? '当前没有匹配的活跃连接' : '启动监视后显示 TCP/UDP 连接',
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
              for (final connection in connections.take(300))
                ListTile(
                  leading: CircleAvatar(
                    child: LocalizedText(
                      connection.protocol,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  title: LocalizedText(
                    '${connection.remoteAddress}:${connection.remotePort}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: LocalizedText(
                    [
                      if (connection.applicationLabel?.isNotEmpty == true)
                        connection.applicationLabel!,
                      if (connection.processName?.isNotEmpty == true)
                        '${connection.processName} (${connection.processId ?? '-'})',
                      'IPv${connection.ipVersion}',
                      connection.applicationProtocol,
                      connection.state,
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showEndpoint(connection),
                ),
            ],
          ),
        ),
    ],
  );

  Future<void> _start() async {
    setState(() {
      _running = true;
      _samples.clear();
      _previous = null;
      _current = null;
      _error = null;
      _sessionRx = 0;
      _sessionTx = 0;
    });
    await _native.startForegroundTask('实时流量监视中', '点击返回应用，可随时停止');
    await _sample();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
  }

  Future<void> _sample() async {
    if (!_running || _sampling) return;
    _sampling = true;
    try {
      final next = await _native.getTrafficSnapshot();
      final previous = _previous;
      if (previous != null &&
          next.totalRxBytes != null &&
          previous.totalRxBytes != null &&
          next.totalTxBytes != null &&
          previous.totalTxBytes != null) {
        final seconds =
            (next.elapsedRealtimeMs - previous.elapsedRealtimeMs) / 1000;
        final rx = (next.totalRxBytes! - previous.totalRxBytes!).clamp(
          0,
          1 << 50,
        );
        final tx = (next.totalTxBytes! - previous.totalTxBytes!).clamp(
          0,
          1 << 50,
        );
        if (seconds > 0) {
          _sessionRx += rx;
          _sessionTx += tx;
          _samples.add(
            TrafficRateSample(
              timestamp: next.timestamp,
              downloadBytesPerSecond: rx / seconds,
              uploadBytesPerSecond: tx / seconds,
              activeConnections: next.connections.length,
            ),
          );
          if (_samples.length > 90) _samples.removeAt(0);
          if (_samples.length % 15 == 0) _refreshAppTraffic();
        }
      }
      _previous = next;
      if (mounted)
        setState(() {
          _current = next;
          _error = null;
        });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _sampling = false;
    }
  }

  Future<void> _refreshAppTraffic() async {
    if (_appLoading) return;
    _appLoading = true;
    if (mounted) setState(() {});
    try {
      final allowed = await _native.hasUsageStatsAccess();
      final rows = allowed
          ? await _native.getAppTrafficStats(
              since: DateTime.now().subtract(const Duration(hours: 1)),
            )
          : const <AppTrafficUsage>[];
      if (mounted) {
        setState(() {
          _usageAccess = allowed;
          _appTraffic = rows;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '应用流量读取失败：$error');
    } finally {
      _appLoading = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    await _native.stopForegroundTask();
    if (mounted) setState(() => _running = false);
  }

  Future<void> _showEndpoint(TrafficConnection connection) async {
    final geoService = GeoIpService(database: widget.appState.database);
    String? hostname;
    GeoIpResult? geo;
    IpOwnershipResult? owner;
    Object? error;
    try {
      hostname = (await InternetAddress(
        connection.remoteAddress,
      ).reverse()).host;
    } on Object {
      /* Reverse DNS is optional. */
    }
    try {
      geo = await geoService.lookup(connection.remoteAddress);
      owner = await IpOwnershipService().lookup(connection.remoteAddress);
    } on Object catch (value) {
      error = value;
    } finally {
      geoService.close();
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalizedText(
              '${connection.remoteAddress}:${connection.remotePort}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            _detail(
              '协议',
              'IPv${connection.ipVersion} / ${connection.protocol} / ${connection.applicationProtocol}',
            ),
            _detail('状态', connection.state),
            _detail(
              '本地端点',
              '${connection.localAddress}:${connection.localPort}',
            ),
            _detail('反向域名', hostname ?? '未解析'),
            _detail(
              '国家/地区',
              geo == null || !geo.success
                  ? '未知'
                  : '${geo.country} ${geo.region} ${geo.city}'.trim(),
            ),
            _detail('网络服务', geo?.isp.isNotEmpty == true ? geo!.isp : '未知'),
            _detail(
              'ASN / 组织',
              owner?.asn == null
                  ? '未知'
                  : 'AS${owner!.asn} · ${owner.asName ?? owner.name ?? ''}',
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LocalizedText(
                  '部分在线归属信息不可用：$error',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static bool _matches(TrafficConnection value, String expression) {
    final input = expression.trim().toLowerCase();
    if (input.isEmpty) return true;
    final clauses = input.split(RegExp(r'\s+and\s+'));
    for (final clause in clauses) {
      if (clause == 'tcp' && value.protocol != 'TCP') return false;
      if (clause == 'udp' && value.protocol != 'UDP') return false;
      if (clause == 'ip6' && value.ipVersion != 6) return false;
      if (clause == 'ip' && value.ipVersion != 4) return false;
      if (clause.startsWith('port ')) {
        final port = int.tryParse(clause.substring(5).trim());
        if (port == null ||
            (value.localPort != port && value.remotePort != port))
          return false;
      }
      if (clause.startsWith('host ')) {
        final host = clause.substring(5).trim();
        if (value.localAddress != host && value.remoteAddress != host)
          return false;
      }
      if (!{'tcp', 'udp', 'ip', 'ip6'}.contains(clause) &&
          !clause.startsWith('port ') &&
          !clause.startsWith('host ')) {
        final haystack =
            '${value.protocol} ${value.applicationProtocol} ${value.localAddress} ${value.remoteAddress} ${value.localPort} ${value.remotePort}'
                .toLowerCase();
        if (!haystack.contains(clause)) return false;
      }
    }
    return true;
  }
}

Widget _legend(Color color, String label) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
    const SizedBox(width: 5),
    LocalizedText(label, style: const TextStyle(fontSize: 12)),
  ],
);

Widget _detail(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 92,
        child: LocalizedText(
          label,
          style: const TextStyle(color: Color(0xFF667185)),
        ),
      ),
      Expanded(child: SelectableText(value)),
    ],
  ),
);

String _rate(double value) {
  if (value >= 1024 * 1024 * 1024)
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  if (value >= 1024 * 1024)
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '${value.toStringAsFixed(0)} B';
}

String _bytes(int value) => _rate(value.toDouble());
