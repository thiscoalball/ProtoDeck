import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../models/network_context.dart';
import '../../../services/native_network_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../services/wifi_analysis_service.dart';
import '../../../services/wifi_quality_service.dart';
import '../../../state/app_state.dart';

enum _WifiBand { all, band24, band5, band6 }

double _channelWidthMHz(String value) {
  final match = RegExp(r'(20|40|80|160|320)').firstMatch(value);
  return double.tryParse(match?.group(1) ?? '') ?? 20;
}

class WifiAnalyzerPage extends StatefulWidget {
  const WifiAnalyzerPage({super.key, required this.appState});
  final AppState appState;
  @override
  State<WifiAnalyzerPage> createState() => _WifiAnalyzerPageState();
}

class _WifiAnalyzerPageState extends State<WifiAnalyzerPage>
    with SingleTickerProviderStateMixin {
  final _native = NativeNetworkService();
  final _search = TextEditingController();
  late final ToolDraftRepository _drafts = ToolDraftRepository(
    widget.appState.database,
  );
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _signalHistory = <int>[];
  final _nearbySignalMonitor = WifiSignalMonitor();
  final _monitoredBssids = <String>{};
  List<WifiAccessPoint> _aps = [];
  NetworkContext? _context;
  Timer? _signalTimer;
  Timer? _nearbyMonitorTimer;
  WifiScanSnapshot? _scanSnapshot;
  String _sort = 'signal';
  String _signalFilter = 'all';
  String _securityFilter = 'all';
  String _widthFilter = 'all';
  _WifiBand _band = _WifiBand.all;
  bool _loading = true;
  String? _error;
  DateTime? _collectedAt;
  DateTime? _lastSignalSample;
  bool _scanFresh = false;
  String _scanStatus = 'unknown';
  Duration? _scanResultAge;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  bool _nearbyMonitorRunning = false;
  bool _nearbyMonitorBusy = false;
  WifiConnectionQualityReport? _connectionQuality;
  bool _qualityLoading = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_saveDraft);
    _tabs.addListener(_saveDraft);
    unawaited(_restoreDraft());
    _load();
    _signalTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _sampleSignal(),
    );
    _nearbyMonitorTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_nearbyMonitorRunning) unawaited(_sampleNearbySignals());
    });
  }

  @override
  void dispose() {
    _signalTimer?.cancel();
    _nearbyMonitorTimer?.cancel();
    unawaited(_drafts.flush('wifi'));
    _drafts.dispose();
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (Platform.isAndroid) {
        final permissions = await [
          Permission.locationWhenInUse,
          Permission.nearbyWifiDevices,
        ].request();
        _permissionDenied = permissions.values.any(
          (status) => status.isDenied || status.isPermanentlyDenied,
        );
        _permissionPermanentlyDenied = permissions.values.any(
          (status) => status.isPermanentlyDenied,
        );
      } else {
        _permissionDenied = false;
        _permissionPermanentlyDenied = false;
      }
      final values = await Future.wait([
        _native.getNetworkContext(),
        _native.scanWifiSnapshot(),
      ]);
      if (!mounted) return;
      final context = values[0] as NetworkContext;
      final scan = values[1] as WifiScanSnapshot;
      setState(() {
        _context = context;
        _aps = scan.accessPoints;
        _scanSnapshot = scan;
        _nearbySignalMonitor.addSnapshot(scan);
        _scanFresh = scan.fresh;
        _scanStatus = scan.status;
        _scanResultAge = scan.newestResultAge;
        _collectedAt = scan.newestResultAge == null
            ? scan.collectedAt
            : scan.collectedAt.subtract(scan.newestResultAge!);
        if (context.wifi?.rssi case final rssi?) _appendSignal(rssi);
        _sortRows();
        if (_monitoredBssids.isEmpty && _aps.isNotEmpty) {
          final current = context.wifi?.bssid?.toUpperCase();
          _monitoredBssids.add(
            _aps.any((ap) => ap.bssid.toUpperCase() == current)
                ? current!
                : _aps.first.bssid.toUpperCase(),
          );
        }
        if (!_supports6Ghz && _band == _WifiBand.band6) {
          _band = _WifiBand.all;
        }
      });
      unawaited(_probeConnectionQuality(context));
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sampleNearbySignals() async {
    if (_nearbyMonitorBusy || !_nearbyMonitorRunning) return;
    _nearbyMonitorBusy = true;
    try {
      final scan = await _native.scanWifiSnapshot();
      if (!mounted || !_nearbyMonitorRunning) return;
      setState(() {
        _scanSnapshot = scan;
        _aps = scan.accessPoints;
        _scanFresh = scan.fresh;
        _scanStatus = scan.status;
        _scanResultAge = scan.newestResultAge;
        _collectedAt = scan.newestResultAge == null
            ? scan.collectedAt
            : scan.collectedAt.subtract(scan.newestResultAge!);
        _nearbySignalMonitor.addSnapshot(scan);
        _sortRows();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _nearbyMonitorBusy = false;
    }
  }

  Future<void> _probeConnectionQuality(NetworkContext network) async {
    if (_qualityLoading) return;
    setState(() => _qualityLoading = true);
    try {
      final report = await const WifiConnectionQualityService().probe(
        network,
        pingGateway: (gateway) => _native.runPing(
          host: gateway,
          count: 3,
          timeoutMs: 1200,
          intervalMs: 250,
          packetSize: 32,
        ),
      );
      if (mounted) setState(() => _connectionQuality = report);
    } on Object {
      // Radio analysis remains useful if an active gateway/DNS probe fails.
    } finally {
      if (mounted) setState(() => _qualityLoading = false);
    }
  }

  bool get _supports6Ghz =>
      _scanSnapshot?.supports6Ghz == true ||
      _aps.any((ap) => ap.frequency >= 5925);

  bool get _supports5Ghz =>
      _scanSnapshot?.supports5Ghz == true ||
      _aps.any((ap) => ap.frequency >= 4900 && ap.frequency < 5925);

  Future<void> _sampleSignal() async {
    try {
      final context = await _native.getNetworkContext();
      final rssi = context.wifi?.rssi;
      if (mounted && rssi != null)
        setState(() {
          _context = context;
          _lastSignalSample = DateTime.now();
          _appendSignal(rssi);
        });
    } on Object {
      // A background sample may fail while Wi-Fi is switching networks.
    }
  }

  void _appendSignal(int rssi) {
    _signalHistory.add(rssi);
    if (_signalHistory.length > 30) _signalHistory.removeAt(0);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('Wi‑Fi'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: context.tr('重新扫描'),
        ),
      ],
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: const [
          Tab(icon: Icon(Icons.wifi), child: LocalizedText('当前连接')),
          Tab(icon: Icon(Icons.radar), child: LocalizedText('附近网络')),
          Tab(icon: Icon(Icons.show_chart), child: LocalizedText('信号监测')),
          Tab(icon: Icon(Icons.bar_chart), child: LocalizedText('信道分析')),
        ],
      ),
    ),
    body: Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          MaterialBanner(
            content: LocalizedText(
              'Wi‑Fi 信息读取失败：$_error\n'
              '${Platform.isWindows
                  ? '请确认 Windows WLAN AutoConfig 服务已启动，并允许系统获取附近网络。'
                  : Platform.isLinux
                  ? '请确认 NetworkManager 与 nmcli 已安装并正在管理无线网卡。'
                  : '请开启 Wi‑Fi、系统位置服务，并授予附近设备和位置权限。'}',
            ),
            actions: [
              TextButton(onPressed: _load, child: const LocalizedText('重试')),
            ],
          ),
        if (_permissionDenied && _error == null)
          MaterialBanner(
            content: const LocalizedText(
              '当前连接仍可使用，但附近 AP、BSSID 或 SSID 可能被 Android 隐藏。请允许“附近的设备”和位置权限，并开启系统位置服务。',
            ),
            actions: [
              if (_permissionPermanentlyDenied)
                TextButton(
                  onPressed: openAppSettings,
                  child: const LocalizedText('打开系统设置'),
                )
              else
                TextButton(
                  onPressed: _load,
                  child: const LocalizedText('重新授权'),
                ),
            ],
          ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _currentTab(),
              _nearbyTab(),
              _signalMonitorTab(),
              _channelsTab(),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _currentTab() {
    final wifi = _context?.wifi;
    final ssid =
        _cleanSsid(wifi?.ssid) ?? _ssidFromScan(wifi?.bssid) ?? 'SSID 暂不可见';
    final matchingAp = wifi?.bssid == null
        ? null
        : _aps
              .where(
                (ap) => ap.bssid.toLowerCase() == wifi!.bssid!.toLowerCase(),
              )
              .firstOrNull;
    final radioQuality = const WifiRadioQualityEvaluator().evaluate(
      rssi: wifi?.rssi,
      linkSpeedMbps: wifi?.linkSpeedMbps,
      accessPoint: matchingAp,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 19),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1028446D),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF35C987),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  LocalizedText(
                    '当前连接',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: LocalizedText(
                      _bandName(wifi?.frequency),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: .9),
                      Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: .12),
                    ],
                  ),
                ),
                child: Center(
                  child: _SignalGlyph(
                    rssi: wifi?.rssi,
                    color: Theme.of(context).colorScheme.primary,
                    size: 58,
                  ),
                ),
              ),
              const SizedBox(height: 7),
              LocalizedText(
                ssid,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 4),
              LocalizedText(
                'CH ${wifi?.channel ?? '—'}  ·  ${wifi?.rssi ?? '—'} dBm  ·  ${wifi?.linkSpeedMbps == null ? '—' : '${wifi!.linkSpeedMbps} Mbps'}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LocalizedText(
                        '无线接入质量',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${radioQuality.score} · ${context.tr(radioQuality.label)}',
                      style: TextStyle(
                        color: _qualityColor(radioQuality.score),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                LinearProgressIndicator(
                  value: radioQuality.score / 100,
                  color: _qualityColor(radioQuality.score),
                  borderRadius: BorderRadius.circular(10),
                ),
                const SizedBox(height: 10),
                LocalizedText(
                  '信号 ${radioQuality.signalScore}/60 · 拥塞 ${radioQuality.congestionScore}/25 · 链路 ${radioQuality.linkScore}/15',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (radioQuality.notes.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  for (final note in radioQuality.notes)
                    LocalizedText(
                      note,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
                const SizedBox(height: 11),
                if (_qualityLoading)
                  const LinearProgressIndicator()
                else if (_connectionQuality case final quality?)
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _qualityChip(
                        _connectionStateLabel(quality.state),
                        _connectionStateColor(quality.state),
                      ),
                      _qualityChip(
                        quality.gatewayReachable
                            ? '网关 ${_latencyText(quality.gatewayLatencyMs)}'
                            : '网关不可达',
                        quality.gatewayReachable
                            ? const Color(0xFF16856F)
                            : const Color(0xFFD54A4A),
                      ),
                      _qualityChip(
                        quality.dnsReachable
                            ? 'DNS ${_latencyText(quality.dnsLatencyMs)}'
                            : 'DNS 失败',
                        quality.dnsReachable
                            ? const Color(0xFF16856F)
                            : const Color(0xFFD54A4A),
                      ),
                      _qualityChip(
                        quality.ipv4Available ? 'IPv4' : '无 IPv4',
                        quality.ipv4Available
                            ? const Color(0xFF3578F6)
                            : const Color(0xFF708090),
                      ),
                      if (quality.ipv6Available)
                        _qualityChip('IPv6', const Color(0xFF3578F6)),
                      if (quality.captivePortal)
                        _qualityChip('认证门户', const Color(0xFFE59000)),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.65,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            _metricCard('BSSID', wifi?.bssid ?? '—', Icons.router_outlined),
            _metricCard(
              'Wi‑Fi 标准',
              wifi?.standard ?? '—',
              Icons.wifi_tethering,
            ),
            _metricCard(
              '频率',
              wifi?.frequency == null ? '—' : '${wifi!.frequency} MHz',
              Icons.graphic_eq,
            ),
            _metricCard(
              '链路速率',
              wifi?.linkSpeedMbps == null ? '—' : '${wifi!.linkSpeedMbps} Mbps',
              Icons.speed,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: LocalizedText(
                '信号历史',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF32B67A),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            LocalizedText(
              '每 2 秒 · ${_signalHistory.length}/30${_lastSignalSample == null ? '' : ' · ${_formatTime(_lastSignalSample!)}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: SizedBox(
              height: 150,
              child: _signalHistory.isEmpty
                  ? const Center(child: LocalizedText('等待采集信号…'))
                  : CustomPaint(
                      painter: _SignalHistoryPainter(
                        _signalHistory,
                        Theme.of(context).colorScheme.primary,
                      ),
                      size: Size.infinite,
                    ),
            ),
          ),
        ),
        if (ssid == 'SSID 暂不可见')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LocalizedText(
              'Android 隐私限制隐藏了 SSID。请确认“附近的设备”和位置权限均已允许，且系统位置服务已开启。',
            ),
          ),
      ],
    );
  }

  Widget _nearbyTab() {
    final rows = _filteredAps;
    final groups = _groupAccessPoints(rows);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: SearchBar(
            controller: _search,
            leading: const Icon(Icons.search),
            hintText: context.tr('搜索 SSID、BSSID 或安全方式'),
            trailing: _search.text.isEmpty
                ? null
                : [
                    IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  ],
            onChanged: (_) => setState(() {}),
          ),
        ),
        _bandFilters(),
        _advancedFilters(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: LocalizedText(
                  '${groups.length} 个网络 / ${rows.length} 个接入点 · ${_scanStatusLabel()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              DropdownButton<String>(
                value: _sort,
                items: const [
                  DropdownMenuItem(value: 'signal', child: LocalizedText('信号')),
                  DropdownMenuItem(value: 'name', child: LocalizedText('名称')),
                  DropdownMenuItem(
                    value: 'channel',
                    child: LocalizedText('信道'),
                  ),
                  DropdownMenuItem(value: 'width', child: LocalizedText('频宽')),
                ],
                onChanged: (value) {
                  setState(() {
                    _sort = value!;
                    _sortRows();
                  });
                  _saveDraft();
                },
              ),
              IconButton(
                tooltip: context.tr('导出当前列表 CSV'),
                onPressed: rows.isEmpty ? null : () => _exportCsv(rows),
                icon: const Icon(Icons.download_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: LocalizedText('没有符合筛选条件的 Wi‑Fi'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    final strongest = group.$2.first;
                    if (group.$2.length == 1) {
                      return Card(child: _accessPointTile(strongest));
                    }
                    return Card(
                      child: ExpansionTile(
                        leading: _SignalGlyph(
                          rssi: strongest.rssi,
                          color: _signalColor(strongest.rssi),
                          size: 34,
                        ),
                        title: LocalizedText(
                          group.$1,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: LocalizedText(
                          '${group.$2.length} 个 BSSID · '
                          '${group.$2.map((ap) => _bandName(ap.frequency)).toSet().join(' / ')} · '
                          '最强 ${strongest.rssi} dBm',
                        ),
                        children: [
                          const Divider(height: 1),
                          for (final ap in group.$2)
                            _accessPointTile(ap, nested: true),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<(String, List<WifiAccessPoint>)> _groupAccessPoints(
    List<WifiAccessPoint> rows,
  ) {
    final grouped = <String, List<WifiAccessPoint>>{};
    for (final ap in rows) {
      final key = ap.ssid.trim().isEmpty
          ? '<隐藏 SSID> · ${ap.bssid}'
          : ap.ssid.trim();
      grouped.putIfAbsent(key, () => []).add(ap);
    }
    final values = grouped.entries.map((entry) {
      entry.value.sort((left, right) => right.rssi.compareTo(left.rssi));
      return (entry.key, entry.value);
    }).toList();
    values.sort(
      (left, right) => right.$2.first.rssi.compareTo(left.$2.first.rssi),
    );
    return values;
  }

  Widget _accessPointTile(
    WifiAccessPoint ap, {
    bool nested = false,
  }) => ListTile(
    contentPadding: EdgeInsets.symmetric(
      horizontal: nested ? 20 : 14,
      vertical: 7,
    ),
    leading: _SignalGlyph(
      rssi: ap.rssi,
      color: _signalColor(ap.rssi),
      size: 34,
    ),
    title: LocalizedText(
      nested ? ap.bssid : (ap.ssid.isEmpty ? '<隐藏 SSID>' : ap.ssid),
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    subtitle: LocalizedText(
      nested
          ? '${_bandName(ap.frequency)} · CH ${ap.channel} · ${ap.channelWidth} · ${ap.securityLabel}'
          : '${_bandName(ap.frequency)} · CH ${ap.channel} · ${ap.securityLabel}\n${ap.bssid}',
    ),
    isThreeLine: !nested,
    trailing: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LocalizedText(
          '${ap.rssi}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const LocalizedText('dBm'),
      ],
    ),
    onTap: () => _showDetails(ap),
  );

  String _scanStatusLabel() {
    if (_scanFresh)
      return '实时扫描 ${_formatTime(_collectedAt ?? DateTime.now())}';
    final age = _scanResultAge;
    final ageText = age == null
        ? ''
        : age.inSeconds < 60
        ? '${age.inSeconds} 秒前'
        : '${age.inMinutes} 分钟前';
    final reason = switch (_scanStatus) {
      'throttled_or_cached' => '系统限制，显示缓存',
      'timeout_cached' => '扫描超时，显示缓存',
      'system_cached' => '系统返回缓存',
      'windows_system_cache' => 'Windows WLAN 系统快照',
      'linux_networkmanager' => 'Linux NetworkManager 实时扫描',
      _ => '缓存结果',
    };
    return ageText.isEmpty ? reason : '$reason · $ageText';
  }

  Widget _signalMonitorTab() {
    final available = [..._aps]..sort((a, b) => b.rssi.compareTo(a.rssi));
    final selected = available
        .where((ap) => _monitoredBssids.contains(ap.bssid.toUpperCase()))
        .take(4)
        .toList(growable: false);
    final histories = _nearbySignalMonitor.samples;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(
                    '接入点信号监测',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const LocalizedText('最多比较 4 个 BSSID；附近网络只在系统返回新扫描样本时更新。'),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                setState(() => _nearbyMonitorRunning = !_nearbyMonitorRunning);
                if (_nearbyMonitorRunning) unawaited(_sampleNearbySignals());
              },
              icon: Icon(
                _nearbyMonitorRunning
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              label: LocalizedText(_nearbyMonitorRunning ? '暂停监测' : '开始监测'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LocalizedText(
                        '选择 BSSID',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: histories.isEmpty
                          ? null
                          : () => setState(_nearbySignalMonitor.clear),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: const LocalizedText('清空样本'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (available.isEmpty)
                  const LocalizedText('本次扫描没有可监测的接入点')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final ap in available.take(20))
                        FilterChip(
                          selected: _monitoredBssids.contains(
                            ap.bssid.toUpperCase(),
                          ),
                          avatar: _SignalGlyph(
                            rssi: ap.rssi,
                            color: _signalColor(ap.rssi),
                            size: 19,
                          ),
                          label: LocalizedText(
                            '${ap.ssid.isEmpty ? '<隐藏 SSID>' : ap.ssid} · ${_shortBssid(ap.bssid)}',
                          ),
                          onSelected: (enabled) {
                            final key = ap.bssid.toUpperCase();
                            setState(() {
                              if (enabled) {
                                if (_monitoredBssids.length < 4) {
                                  _monitoredBssids.add(key);
                                }
                              } else {
                                _monitoredBssids.remove(key);
                              }
                            });
                          },
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LocalizedText(
                        '信号强度时间线',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_nearbyMonitorBusy)
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                LocalizedText(
                  '${_scanStatusLabel()} · 纵轴 0 ～ -100 dBm',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 260,
                  child:
                      selected.isEmpty ||
                          selected.every(
                            (ap) =>
                                histories[ap.bssid.toUpperCase()]?.isEmpty !=
                                false,
                          )
                      ? const Center(child: LocalizedText('选择接入点并开始监测后显示曲线'))
                      : CustomPaint(
                          size: Size.infinite,
                          painter: _MultiSignalHistoryPainter(
                            series: {
                              for (
                                var index = 0;
                                index < selected.length;
                                index++
                              )
                                selected[index].bssid.toUpperCase():
                                    histories[selected[index].bssid
                                        .toUpperCase()] ??
                                    const [],
                            },
                            colors: {
                              for (
                                var index = 0;
                                index < selected.length;
                                index++
                              )
                                selected[index].bssid.toUpperCase():
                                    _seriesColor(index),
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < selected.length; index++)
          _signalStatisticsCard(
            selected[index],
            histories[selected[index].bssid.toUpperCase()] ?? const [],
            _seriesColor(index),
          ),
      ],
    );
  }

  Widget _signalStatisticsCard(
    WifiAccessPoint accessPoint,
    List<WifiSignalSample> samples,
    Color color,
  ) {
    final values = samples.map((sample) => sample.rssi).toList();
    final minimum = values.isEmpty ? null : values.reduce(math.min);
    final maximum = values.isEmpty ? null : values.reduce(math.max);
    final average = values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
    final variation = values.length < 2
        ? null
        : math.sqrt(
            values.fold<double>(
                  0,
                  (sum, value) => sum + math.pow(value - average!, 2),
                ) /
                values.length,
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LocalizedText(
                    '${accessPoint.ssid.isEmpty ? '<隐藏 SSID>' : accessPoint.ssid} · ${accessPoint.bssid}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                LocalizedText('${accessPoint.rssi} dBm'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _compactMetric('样本', '${samples.length}')),
                Expanded(
                  child: _compactMetric(
                    '最低 / 最高',
                    minimum == null ? '—' : '$minimum / $maximum dBm',
                  ),
                ),
                Expanded(
                  child: _compactMetric(
                    '平均 / 波动',
                    average == null
                        ? '—'
                        : '${average.toStringAsFixed(1)} / ${variation?.toStringAsFixed(1) ?? '—'} dB',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactMetric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LocalizedText(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
      LocalizedText(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  String _shortBssid(String value) =>
      value.length <= 8 ? value : value.substring(value.length - 8);

  Color _seriesColor(int index) => const [
    Color(0xFF3578F6),
    Color(0xFF00A58C),
    Color(0xFFF18F3B),
    Color(0xFF9B67D8),
  ][index % 4];

  Widget _channelsTab() {
    final selectedBand = _band == _WifiBand.all ? _WifiBand.band24 : _band;
    final rows = _aps.where((ap) => _apBand(ap) == selectedBand).toList();
    final scores = _channelScores(rows, selectedBand);
    final busiest = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LocalizedText(
          '信道拥挤程度',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const LocalizedText('柱越高表示同信道及相邻信道的接入点越多、信号越强。该图基于本次扫描结果，不代表实际吞吐。'),
        const SizedBox(height: 10),
        _bandFilters(channelMode: true),
        const SizedBox(height: 12),
        ..._spectrumSections(rows, selectedBand),
        _recommendationCard(selectedBand),
        const SizedBox(height: 12),
        Card(
          child: SizedBox(
            height: 270,
            child: scores.isEmpty
                ? const Center(child: LocalizedText('该频段暂未扫描到接入点'))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
                    child: CustomPaint(
                      size: Size(
                        math.max(
                          MediaQuery.sizeOf(context).width - 60,
                          scores.length * 38,
                        ),
                        235,
                      ),
                      painter: _ChannelChartPainter(
                        scores,
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        if (busiest.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LocalizedText(
                    '拥挤信道排行',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...busiest
                      .take(5)
                      .map(
                        (entry) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 58,
                                child: LocalizedText('CH ${entry.key}'),
                              ),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value:
                                      entry.value /
                                      math.max(.001, busiest.first.value),
                                ),
                              ),
                              const SizedBox(width: 10),
                              LocalizedText(entry.value.toStringAsFixed(1)),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _bandFilters({bool channelMode = false}) {
    final bands = <_WifiBand>[
      if (!channelMode) _WifiBand.all,
      _WifiBand.band24,
      if (_supports5Ghz) _WifiBand.band5,
      if (_supports6Ghz) _WifiBand.band6,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: bands
            .map(
              (band) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected:
                      (channelMode && _band == _WifiBand.all
                          ? _WifiBand.band24
                          : _band) ==
                      band,
                  label: LocalizedText(switch (band) {
                    _WifiBand.all => '全部',
                    _WifiBand.band24 => '2.4 GHz',
                    _WifiBand.band5 => '5 GHz',
                    _WifiBand.band6 => '6 GHz',
                  }),
                  onSelected: (_) {
                    setState(() => _band = band);
                    _saveDraft();
                  },
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _advancedFilters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
    child: Row(
      children: [
        _filterMenu(
          icon: Icons.signal_cellular_alt_rounded,
          value: _signalFilter,
          items: const {
            'all': '全部信号',
            'strong': '强信号（≥ -60 dBm）',
            'usable': '可用信号（≥ -75 dBm）',
            'weak': '弱信号（< -75 dBm）',
          },
          onChanged: (value) {
            setState(() => _signalFilter = value);
            _saveDraft();
          },
        ),
        const SizedBox(width: 8),
        _filterMenu(
          icon: Icons.security_rounded,
          value: _securityFilter,
          items: const {'all': '全部安全方式', 'secured': '仅加密网络', 'open': '仅开放网络'},
          onChanged: (value) {
            setState(() => _securityFilter = value);
            _saveDraft();
          },
        ),
        const SizedBox(width: 8),
        _filterMenu(
          icon: Icons.width_wide_rounded,
          value: _widthFilter,
          items: const {
            'all': '全部频宽',
            '20': '20 MHz',
            '40': '40 MHz',
            '80': '80 MHz',
            '160+': '160 / 320 MHz',
          },
          onChanged: (value) {
            setState(() => _widthFilter = value);
            _saveDraft();
          },
        ),
      ],
    ),
  );

  Widget _filterMenu({
    required IconData icon,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) => PopupMenuButton<String>(
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (context) => [
      for (final entry in items.entries)
        PopupMenuItem(value: entry.key, child: LocalizedText(entry.value)),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 7),
          LocalizedText(items[value]!),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down_rounded, size: 19),
        ],
      ),
    ),
  );

  Widget _metricCard(String label, String value, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 3),
                LocalizedText(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  List<WifiAccessPoint> get _filteredAps {
    final query = _search.text.trim().toLowerCase();
    return _aps.where((ap) {
      final matchesBand = _band == _WifiBand.all || _apBand(ap) == _band;
      final matchesQuery =
          query.isEmpty ||
          ap.ssid.toLowerCase().contains(query) ||
          ap.bssid.toLowerCase().contains(query) ||
          ap.security.toLowerCase().contains(query);
      final matchesSignal = switch (_signalFilter) {
        'strong' => ap.rssi >= -60,
        'usable' => ap.rssi >= -75,
        'weak' => ap.rssi < -75,
        _ => true,
      };
      final security = ap.security.toLowerCase();
      final open =
          security.isEmpty ||
          security.contains('open') ||
          security.contains('none');
      final matchesSecurity = switch (_securityFilter) {
        'secured' => !open,
        'open' => open,
        _ => true,
      };
      final width = _channelWidthMHz(ap.channelWidth).round();
      final matchesWidth = switch (_widthFilter) {
        '20' => width == 20,
        '40' => width == 40,
        '80' => width == 80,
        '160+' => width >= 160,
        _ => true,
      };
      return matchesBand &&
          matchesQuery &&
          matchesSignal &&
          matchesSecurity &&
          matchesWidth;
    }).toList();
  }

  void _sortRows() {
    _aps.sort(
      (a, b) => switch (_sort) {
        'name' => a.ssid.compareTo(b.ssid),
        'channel' => a.channel.compareTo(b.channel),
        'width' => _channelWidthMHz(
          b.channelWidth,
        ).compareTo(_channelWidthMHz(a.channelWidth)),
        _ => b.rssi.compareTo(a.rssi),
      },
    );
  }

  void _saveDraft() {
    _drafts.scheduleSave('wifi', {
      'tab': _tabs.index,
      'query': _search.text,
      'sort': _sort,
      'band': _band.name,
      'signalFilter': _signalFilter,
      'securityFilter': _securityFilter,
      'widthFilter': _widthFilter,
    });
  }

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('wifi');
    if (!mounted || draft == null) return;
    final payload = draft.payload;
    final bandName = payload['band']?.toString();
    setState(() {
      _search.text = payload['query']?.toString() ?? '';
      _sort = switch (payload['sort']) {
        'name' => 'name',
        'channel' => 'channel',
        _ => 'signal',
      };
      _band = _WifiBand.values.firstWhere(
        (value) => value.name == bandName,
        orElse: () => _WifiBand.all,
      );
      _signalFilter =
          const {
            'all',
            'strong',
            'usable',
            'weak',
          }.contains(payload['signalFilter'])
          ? payload['signalFilter']!.toString()
          : 'all';
      _securityFilter =
          const {'all', 'secured', 'open'}.contains(payload['securityFilter'])
          ? payload['securityFilter']!.toString()
          : 'all';
      _widthFilter =
          const {
            'all',
            '20',
            '40',
            '80',
            '160+',
          }.contains(payload['widthFilter'])
          ? payload['widthFilter']!.toString()
          : 'all';
    });
    final tab = (payload['tab'] as num?)?.toInt().clamp(0, 3) ?? 0;
    _tabs.index = tab;
  }

  Future<void> _exportCsv(List<WifiAccessPoint> rows) async {
    try {
      final csvText = Csv().encode([
        const [
          'SSID',
          'BSSID',
          'Band',
          'Channel',
          'Width',
          'Frequency MHz',
          'RSSI dBm',
          'Security',
        ],
        for (final ap in rows)
          [
            _safeCsvCell(ap.ssid),
            _safeCsvCell(ap.bssid),
            _bandName(ap.frequency),
            ap.channel,
            ap.channelWidth,
            ap.frequency,
            ap.rssi,
            _safeCsvCell(ap.securityLabel),
          ],
      ]);
      final bytes = Uint8List.fromList([
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(csvText),
      ]);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: context.tr('导出 Wi‑Fi 扫描结果'),
        fileName: 'protodeck_wifi_${DateTime.now().millisecondsSinceEpoch}.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: bytes,
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

  String _safeCsvCell(String value) {
    final trimmedLeft = value.trimLeft();
    return trimmedLeft.startsWith(RegExp(r'[=+\-@]')) ? "'$value" : value;
  }

  void _showDetails(WifiAccessPoint ap) {
    final sameSsid = _aps.where((value) => value.ssid == ap.ssid).toList();
    final findings = const WifiSecurityAnalyzer().inspect(
      ap,
      sameSsid: sameSsid,
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Row(
                children: [
                  _SignalGlyph(
                    rssi: ap.rssi,
                    color: _signalColor(ap.rssi),
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LocalizedText(
                      ap.ssid.isEmpty ? '<隐藏 SSID>' : ap.ssid,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() {
                        if (_monitoredBssids.length >= 4 &&
                            !_monitoredBssids.contains(
                              ap.bssid.toUpperCase(),
                            )) {
                          _monitoredBssids.remove(_monitoredBssids.first);
                        }
                        _monitoredBssids.add(ap.bssid.toUpperCase());
                        _tabs.index = 2;
                      });
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.show_chart_rounded, size: 18),
                    label: const LocalizedText('监测'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      ap.ssid.trim().isEmpty || !_canRequestConnection(ap)
                      ? null
                      : () {
                          Navigator.pop(context);
                          unawaited(_connectToAccessPoint(ap));
                        },
                  icon: const Icon(Icons.wifi_find_rounded),
                  label: LocalizedText(
                    Platform.isWindows ? '连接已保存的网络' : '请求连接此 Wi‑Fi',
                  ),
                ),
              ),
              if (Platform.isAndroid &&
                  _scanSnapshot?.supportsRtt == true &&
                  ap.rttResponder) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(_runWifiRtt(ap));
                    },
                    icon: const Icon(Icons.radar_rounded),
                    label: const LocalizedText('Wi‑Fi RTT 测距'),
                  ),
                ),
              ],
              if (!_canRequestConnection(ap))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LocalizedText(
                    '企业认证或 WEP 网络需要证书/身份等额外配置，请使用系统 Wi‑Fi 设置。',
                  ),
                ),
              const Divider(height: 28),
              _detail('BSSID', ap.bssid),
              _detail('信号强度', '${ap.rssi} dBm · ${_signalLabel(ap.rssi)}'),
              _detail(
                '频段 / 信道',
                '${_bandName(ap.frequency)} · CH ${ap.channel}',
              ),
              _detail('中心频率', '${ap.frequency} MHz'),
              _detail('信道宽度', ap.channelWidth),
              if (ap.standard != null) _detail('Wi‑Fi 标准', ap.standard!),
              if (ap.centerFrequency0 != null)
                _detail('中心频率 0', '${ap.centerFrequency0} MHz'),
              if (ap.centerFrequency1 != null)
                _detail('中心频率 1', '${ap.centerFrequency1} MHz'),
              _detail('安全方式', ap.securityLabel),
              if (ap.stationCount != null)
                _detail('关联终端数（AP 报告）', '${ap.stationCount}'),
              if (ap.channelUtilizationPercent != null)
                _detail('信道利用率（AP 报告）', '${ap.channelUtilizationPercent}%'),
              if (ap.dtimPeriod != null) _detail('DTIM 周期', '${ap.dtimPeriod}'),
              if (ap.supports80211k != null)
                _detail('802.11k', ap.supports80211k! ? '支持' : '未发现'),
              if (ap.supports80211v != null)
                _detail('802.11v', ap.supports80211v! ? '支持' : '未发现'),
              if (ap.supports80211r != null)
                _detail('802.11r', ap.supports80211r! ? '支持' : '未发现'),
              if (ap.pmfCapable != null)
                _detail(
                  '管理帧保护 PMF',
                  ap.pmfRequired == true
                      ? '强制'
                      : ap.pmfCapable == true
                      ? '支持但未强制'
                      : '未发现',
                ),
              if (ap.rttResponder) _detail('Wi‑Fi RTT / FTM', '支持'),
              if (ap.passpoint) _detail('Passpoint', '支持'),
              _detail(
                '采集时间',
                _collectedAt == null ? '—' : _collectedAt.toString(),
              ),
              const SizedBox(height: 18),
              LocalizedText(
                '安全检查',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              for (final finding in findings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    switch (finding.severity) {
                      WifiSecuritySeverity.info => Icons.info_outline_rounded,
                      WifiSecuritySeverity.warning =>
                        Icons.warning_amber_rounded,
                      WifiSecuritySeverity.critical => Icons.gpp_bad_outlined,
                    },
                    color: switch (finding.severity) {
                      WifiSecuritySeverity.info => Theme.of(
                        context,
                      ).colorScheme.primary,
                      WifiSecuritySeverity.warning => const Color(0xFFE59000),
                      WifiSecuritySeverity.critical => Theme.of(
                        context,
                      ).colorScheme.error,
                    },
                  ),
                  title: LocalizedText(finding.title),
                  subtitle: LocalizedText(finding.detail),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _connectToAccessPoint(WifiAccessPoint ap) async {
    final security = ap.security.toLowerCase();
    final isOpen =
        security.isEmpty ||
        security.contains('open') ||
        security.contains('none') ||
        security.contains('owe') ||
        security == '--';
    final passwordController = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('连接 Wi‑Fi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalizedText(
              '${ap.ssid} · ${ap.securityLabel} · CH ${ap.channel}',
            ),
            const SizedBox(height: 12),
            if (Platform.isWindows)
              const LocalizedText(
                'Windows 将使用系统中已经保存的 WLAN 配置文件。ProtoDeck 不会读取系统保存的密码。',
              )
            else if (!isOpen)
              TextField(
                controller: passwordController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  label: LocalizedText('Wi‑Fi 密码'),
                  helper: LocalizedText('密码仅用于本次系统连接请求，不会保存到工具草稿。'),
                ),
              ),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 12),
              const LocalizedText(
                'Android 将打开系统确认界面；最终是否保存和连接由系统与用户决定。连接局域网不要求具备公网出口。',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('继续'),
          ),
        ],
      ),
    );
    final password = passwordController.text;
    passwordController.dispose();
    if (approved != true || !mounted) return;
    if (!isOpen && !Platform.isWindows && password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Wi‑Fi 密码至少需要 8 个字符。')),
      );
      return;
    }
    try {
      final result = await _native.requestWifiConnection(
        ssid: ap.ssid,
        security: ap.security,
        password: password,
        interfaceName: _context?.interfaceName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
            result.systemUiOpened
                ? '已打开系统 Wi‑Fi 确认界面。'
                : '连接请求已提交：${result.message ?? result.status}',
          ),
        ),
      );
      if (!result.systemUiOpened) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) await _load();
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText('Wi‑Fi 连接请求失败：$error')));
    }
  }

  bool _canRequestConnection(WifiAccessPoint ap) {
    if (Platform.isWindows) return true;
    final security = ap.security.toLowerCase();
    return !security.contains('eap') &&
        !security.contains('enterprise') &&
        !security.contains('wep');
  }

  Future<void> _runWifiRtt(WifiAccessPoint ap) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: LocalizedText('正在执行 FTM 测距…')),
    );
    try {
      final measurement = await _native.runWifiRtt(ap.bssid);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const LocalizedText('Wi‑Fi RTT 测距结果'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(ap.ssid),
              const SizedBox(height: 12),
              LocalizedText(
                '${(measurement.distanceMm / 1000).toStringAsFixed(2)} m '
                '± ${(measurement.distanceStdDevMm / 1000).toStringAsFixed(2)} m',
                style: Theme.of(dialogContext).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              LocalizedText(
                'RSSI ${measurement.rssi ?? '—'} dBm · '
                '${measurement.successfulMeasurements}/${measurement.attemptedMeasurements} 次有效测量',
              ),
              const SizedBox(height: 8),
              const LocalizedText(
                '距离来自 802.11mc FTM 往返时间估算，会受 AP 校准、多径和设备实现影响。',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const LocalizedText('关闭'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: LocalizedText('Wi‑Fi RTT 测距失败：$error')),
      );
    }
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 100, child: LocalizedText(label)),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );

  List<Widget> _spectrumSections(List<WifiAccessPoint> rows, _WifiBand band) {
    List<Widget> chart(
      String title,
      List<WifiAccessPoint> points,
      double min,
      double max,
      List<int> channelTicks,
    ) => [
      LocalizedText(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      Card(
        child: SizedBox(
          height: 280,
          child: points.isEmpty
              ? const Center(child: LocalizedText('本次扫描未发现该频段网络'))
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _WifiSpectrumPainter(
                      points,
                      min,
                      max,
                      channelTicks,
                    ),
                  ),
                ),
        ),
      ),
      const SizedBox(height: 14),
    ];
    if (band == _WifiBand.band24) {
      return chart('频宽与信号强度 · 2.4 GHz', rows, 2400, 2484, const [
        1,
        3,
        5,
        7,
        9,
        11,
        13,
      ]);
    }
    if (band == _WifiBand.band5) {
      return [
        ...chart(
          '频宽与信号强度 · 5 GHz 低频（室内）',
          rows.where((ap) => ap.frequency <= 5350).toList(),
          5150,
          5350,
          const [36, 40, 44, 48, 52, 56, 60, 64],
        ),
        ...chart(
          '频宽与信号强度 · 5 GHz 高频',
          rows.where((ap) => ap.frequency >= 5725).toList(),
          5725,
          5850,
          const [149, 153, 157, 161, 165],
        ),
      ];
    }
    final frequencies = rows.map((ap) => ap.frequency).toList();
    final min = frequencies.isEmpty
        ? 5925.0
        : frequencies.reduce(math.min) - 80.0;
    final max = frequencies.isEmpty
        ? 7125.0
        : frequencies.reduce(math.max) + 80.0;
    final ticks = <int>{for (final ap in rows) ap.channel}.toList()..sort();
    return chart(
      '频宽与信号强度 · 6 GHz（仅展示扫描）',
      rows,
      min,
      max,
      ticks.length > 8
          ? ticks.where((c) => ticks.indexOf(c).isEven).toList()
          : ticks,
    );
  }

  Widget _recommendationCard(_WifiBand band) {
    final (minimum, maximum) = switch (band) {
      _WifiBand.band24 => (2400, 2484),
      _WifiBand.band5 => (4900, 5924),
      _WifiBand.band6 => (5925, 7125),
      _ => (2400, 2484),
    };
    final usable =
        _scanSnapshot?.usableChannels
            .where(
              (channel) =>
                  channel.frequency >= minimum && channel.frequency <= maximum,
            )
            .toList(growable: false) ??
        const <WifiUsableChannel>[];
    final ranked = const WifiChannelAdvisor().recommend(
      accessPoints: _aps,
      minimumFrequency: minimum,
      maximumFrequency: maximum,
      usableFrequencies: usable.map((value) => value.frequency).toList(),
    );
    if (ranked.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline_rounded),
          title: LocalizedText('暂时无法生成信道建议'),
          subtitle: LocalizedText('平台没有返回当前频段的可用信道或扫描结果。'),
        ),
      );
    }
    return Card(
      color: const Color(0xFFEAF5FF),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.recommend_outlined, color: Color(0xFF1976D2)),
                const SizedBox(width: 9),
                LocalizedText(
                  '推荐信道',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...ranked.take(3).toList().asMap().entries.map((item) {
              final recommendation = item.value;
              final usableChannel = usable
                  .where((value) => value.frequency == recommendation.frequency)
                  .firstOrNull;
              final width = usableChannel?.maximumWidthMhz ?? 20;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      child: LocalizedText(
                        '${item.key + 1}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LocalizedText(
                        '信道 ${recommendation.channel} · ${recommendation.frequency} MHz · 可用频宽 ≤ $width MHz',
                      ),
                    ),
                    LocalizedText(
                      '评分 ${recommendation.score.toStringAsFixed(1)}',
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            LocalizedText(
              usable.isNotEmpty
                  ? '候选信道来自系统当前监管域和设备约束；评分结合 RSSI、频宽重叠和可用的 BSS Load。'
                  : '平台未提供监管域可用信道，本次仅对实际观察到的信道排序，无法证明未扫描到的信道可用。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Map<int, double> _channelScores(List<WifiAccessPoint> rows, _WifiBand band) {
    final channels = <int>{for (final ap in rows) ap.channel}.toList()..sort();
    if (band == _WifiBand.band24) {
      channels
        ..clear()
        ..addAll(List.generate(14, (i) => i + 1));
    } else if (band == _WifiBand.band5) {
      channels
        ..clear()
        ..addAll(const [
          36,
          40,
          44,
          48,
          52,
          56,
          60,
          64,
          149,
          153,
          157,
          161,
          165,
        ]);
    }
    return {
      for (final channel in channels)
        channel: rows.fold(0.0, (score, ap) {
          final strength = ((ap.rssi + 100).clamp(5, 70)) / 70;
          final distance = (ap.channel - channel).abs();
          final overlap = band == _WifiBand.band24
              ? math.max(0.0, 1 - distance / 3.5)
              : band == _WifiBand.band5
              ? math.max(
                  0.0,
                  1 -
                      (ap.frequency - _frequencyForChannel(channel)).abs() /
                          ((_channelWidthMHz(ap.channelWidth) + 20) / 2),
                )
              : (distance == 0 ? 1.0 : 0.0);
          return score + strength * overlap;
        }),
    };
  }

  int _frequencyForChannel(int channel) => 5000 + channel * 5;

  _WifiBand _apBand(WifiAccessPoint ap) => ap.frequency >= 5925
      ? _WifiBand.band6
      : ap.frequency >= 4900
      ? _WifiBand.band5
      : _WifiBand.band24;
  String _bandName(int? frequency) => frequency == null
      ? '未知频段'
      : frequency >= 5925
      ? '6 GHz'
      : frequency >= 4900
      ? '5 GHz'
      : '2.4 GHz';
  String? _cleanSsid(String? ssid) =>
      ssid == null || ssid.isEmpty || ssid.toLowerCase().contains('unknown')
      ? null
      : ssid;
  String? _ssidFromScan(String? bssid) {
    if (bssid == null) return null;
    for (final ap in _aps) {
      if (ap.bssid.toLowerCase() == bssid.toLowerCase())
        return _cleanSsid(ap.ssid);
    }
    return null;
  }

  Color _signalColor(int rssi) => rssi >= -60
      ? const Color(0xFF16856F)
      : rssi >= -72
      ? const Color(0xFFE59000)
      : const Color(0xFFD54A4A);
  Color _qualityColor(int score) => score >= 70
      ? const Color(0xFF16856F)
      : score >= 50
      ? const Color(0xFFE59000)
      : const Color(0xFFD54A4A);
  Color _connectionStateColor(WifiConnectionState state) => switch (state) {
    WifiConnectionState.internetHealthy => const Color(0xFF16856F),
    WifiConnectionState.localOnly => const Color(0xFF3578F6),
    WifiConnectionState.degraded => const Color(0xFFE59000),
    WifiConnectionState.offline => const Color(0xFFD54A4A),
  };
  String _connectionStateLabel(WifiConnectionState state) => switch (state) {
    WifiConnectionState.internetHealthy => '互联网可用',
    WifiConnectionState.localOnly => '局域网可用',
    WifiConnectionState.degraded => '连接受限',
    WifiConnectionState.offline => '网络不可用',
  };
  String _latencyText(double? value) =>
      value == null ? '可达' : '${value.toStringAsFixed(1)} ms';

  Widget _qualityChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(999),
    ),
    child: LocalizedText(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
  String _signalLabel(int rssi) => rssi >= -55
      ? '极佳'
      : rssi >= -65
      ? '良好'
      : rssi >= -75
      ? '一般'
      : '较弱';
  String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
}

class _SignalGlyph extends StatelessWidget {
  const _SignalGlyph({
    required this.rssi,
    required this.color,
    required this.size,
  });
  final int? rssi;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _WifiWavePainter(rssi ?? -100, color)),
    );
  }
}

class _SignalHistoryPainter extends CustomPainter {
  _SignalHistoryPainter(this.values, this.color);
  final List<int> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const plotLeft = 34.0;
    const plotTop = 8.0;
    const plotBottomPadding = 18.0;
    final plotBottom = size.height - plotBottomPadding;
    final plotHeight = plotBottom - plotTop;
    final plotWidth = size.width - plotLeft - 8;
    double yFor(num dbm) =>
        plotTop + ((0 - dbm).clamp(0, 100) / 100) * plotHeight;
    final grid = Paint()
      ..color = color.withValues(alpha: .12)
      ..strokeWidth = 1;
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (final dbm in [0, -20, -40, -60, -80, -100]) {
      final y = yFor(dbm);
      canvas.drawLine(Offset(plotLeft, y), Offset(size.width - 8, y), grid);
      text.text = TextSpan(
        text: '$dbm',
        style: TextStyle(fontSize: 10, color: color.withValues(alpha: .7)),
      );
      text.layout();
      text.paint(canvas, Offset(0, y - 6));
    }
    if (values.isEmpty) return;
    final path = Path();
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = plotLeft + i / math.max(1, values.length - 1) * plotWidth;
      final y = yFor(values[i]);
      points.add(Offset(x, y));
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    final area = Path.from(path)
      ..lineTo(points.last.dx, plotBottom)
      ..lineTo(points.first.dx, plotBottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: .22),
                color.withValues(alpha: .025),
              ],
            ).createShader(
              Rect.fromLTRB(plotLeft, plotTop, size.width, plotBottom),
            ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 2.4, Paint()..color = Colors.white);
      canvas.drawCircle(
        point,
        2.4,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    final latest = points.last;
    canvas.drawCircle(
      latest,
      5.5,
      Paint()..color = color.withValues(alpha: .22),
    );
    canvas.drawCircle(latest, 3.2, Paint()..color = color);
    text.text = TextSpan(
      text: '${values.last} dBm',
      style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
    );
    text.layout();
    final labelX = (latest.dx - text.width).clamp(
      plotLeft,
      size.width - text.width - 4,
    );
    final labelY = latest.dy < 22 ? latest.dy + 7 : latest.dy - 17;
    text.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant _SignalHistoryPainter old) => true;
}

class _MultiSignalHistoryPainter extends CustomPainter {
  _MultiSignalHistoryPainter({required this.series, required this.colors});

  final Map<String, List<WifiSignalSample>> series;
  final Map<String, Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0;
    const top = 10.0;
    const bottom = 26.0;
    final plot = Rect.fromLTRB(left, top, size.width - 8, size.height - bottom);
    final labels = TextPainter(textDirection: TextDirection.ltr);
    final grid = Paint()
      ..color = const Color(0xFF8EB8D8).withValues(alpha: .2)
      ..strokeWidth = 1;
    double yFor(int rssi) =>
        plot.top + ((0 - rssi).clamp(0, 100) / 100) * plot.height;
    for (final dbm in [0, -20, -40, -60, -80, -100]) {
      final y = yFor(dbm);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      labels.text = TextSpan(
        text: '$dbm',
        style: const TextStyle(fontSize: 9, color: Color(0xFF66859D)),
      );
      labels.layout();
      labels.paint(canvas, Offset(2, y - 5));
    }
    final all = series.values.expand((values) => values).toList();
    if (all.isEmpty) return;
    final first = all
        .map((sample) => sample.timestamp)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final last = all
        .map((sample) => sample.timestamp)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final rangeMs = math.max(1, last.difference(first).inMilliseconds);
    double xFor(DateTime timestamp) =>
        plot.left +
        timestamp.difference(first).inMilliseconds / rangeMs * plot.width;

    for (final entry in series.entries) {
      final values = [...entry.value]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (values.isEmpty) continue;
      final color = colors[entry.key] ?? const Color(0xFF3578F6);
      final path = Path();
      for (var index = 0; index < values.length; index++) {
        final sample = values[index];
        final point = Offset(xFor(sample.timestamp), yFor(sample.rssi));
        final gap = index == 0
            ? Duration.zero
            : sample.timestamp.difference(values[index - 1].timestamp);
        if (index == 0 || gap > const Duration(seconds: 45)) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawCircle(
          point,
          2.6,
          Paint()
            ..color = sample.fresh ? color : Colors.white
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          point,
          2.6,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    labels.text = TextSpan(
      text: _time(first),
      style: const TextStyle(fontSize: 9, color: Color(0xFF66859D)),
    );
    labels.layout();
    labels.paint(canvas, Offset(plot.left, plot.bottom + 6));
    labels.text = TextSpan(
      text: _time(last),
      style: const TextStyle(fontSize: 9, color: Color(0xFF66859D)),
    );
    labels.layout();
    labels.paint(canvas, Offset(plot.right - labels.width, plot.bottom + 6));
  }

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';

  @override
  bool shouldRepaint(covariant _MultiSignalHistoryPainter old) => true;
}

class _WifiWavePainter extends CustomPainter {
  _WifiWavePainter(this.rssi, this.color);
  final int rssi;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .78);
    final active = rssi >= -55
        ? 4
        : rssi >= -65
        ? 3
        : rssi >= -75
        ? 2
        : 1;
    for (var index = 1; index <= 4; index++) {
      final radius = size.width * (.10 + index * .105);
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        math.pi * 1.18,
        math.pi * .64,
        false,
        Paint()
          ..color = index <= active ? color : color.withValues(alpha: .18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, size.width * .065)
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(center, size.width * .07, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _WifiWavePainter old) =>
      old.rssi != rssi || old.color != color;
}

class _WifiSpectrumPainter extends CustomPainter {
  _WifiSpectrumPainter(
    this.accessPoints,
    this.minMHz,
    this.maxMHz,
    this.channelTicks,
  );
  final List<WifiAccessPoint> accessPoints;
  final double minMHz;
  final double maxMHz;
  final List<int> channelTicks;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    const bottom = 40.0;
    final plot = Rect.fromLTRB(left, 8, size.width - 5, size.height - bottom);
    final gridPaint = Paint()
      ..color = const Color(0xFF8EB8D8).withValues(alpha: .22)
      ..strokeWidth = 1;
    final text = TextPainter(textDirection: TextDirection.ltr);
    double yFor(double dbm) =>
        plot.top + ((-20 - dbm).clamp(0, 80) / 80) * plot.height;
    double xFor(double mhz) =>
        plot.left +
        ((mhz - minMHz) / (maxMHz - minMHz)).clamp(0, 1) * plot.width;
    for (final dbm in [-20, -40, -60, -80, -100]) {
      final y = yFor(dbm.toDouble());
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      text.text = TextSpan(
        text: '$dbm',
        style: const TextStyle(fontSize: 9, color: Color(0xFF66859D)),
      );
      text.layout();
      text.paint(canvas, Offset(2, y - 5));
    }
    final sorted = [...accessPoints]..sort((a, b) => a.rssi.compareTo(b.rssi));
    for (final ap in sorted) {
      final width = _channelWidthMHz(ap.channelWidth);
      final leftX = xFor(ap.frequency - width / 2);
      final rightX = xFor(ap.frequency + width / 2);
      final shoulder = math.min(12.0, (rightX - leftX) * .18);
      final topY = yFor(ap.rssi.toDouble());
      final bottomY = yFor(-100);
      final hue = (ap.bssid.hashCode.abs() % 360).toDouble();
      final color = HSLColor.fromAHSL(1, hue, .72, .50).toColor();
      final shape = Path()
        ..moveTo(leftX, bottomY)
        ..lineTo(leftX + shoulder, topY)
        ..lineTo(rightX - shoulder, topY)
        ..lineTo(rightX, bottomY)
        ..close();
      canvas.drawPath(shape, Paint()..color = color.withValues(alpha: .13));
      canvas.drawPath(
        shape,
        Paint()
          ..color = color.withValues(alpha: .82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      final label = ap.ssid.isEmpty
          ? ap.bssid.substring(0, math.min(8, ap.bssid.length))
          : ap.ssid;
      text.text = TextSpan(
        text: '$label ${ap.channel}(${width.toInt()})',
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      );
      text.layout(maxWidth: math.max(35, rightX - leftX));
      text.paint(
        canvas,
        Offset(
          (leftX + 3).clamp(plot.left, plot.right - text.width),
          topY - 13,
        ),
      );
    }
    for (final channel in channelTicks) {
      final mhz = minMHz < 2500
          ? (channel == 14 ? 2484.0 : 2407.0 + channel * 5)
          : minMHz >= 5900
          ? 5950.0 + channel * 5
          : 5000.0 + channel * 5;
      final x = xFor(mhz);
      text.text = TextSpan(
        text: 'CH $channel\n${mhz.round()}',
        style: const TextStyle(
          fontSize: 8,
          height: 1.15,
          color: Color(0xFF557A96),
          fontWeight: FontWeight.w600,
        ),
      );
      text.layout();
      text.paint(canvas, Offset(x - text.width / 2, plot.bottom + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _WifiSpectrumPainter old) => true;
}

class _ChannelChartPainter extends CustomPainter {
  _ChannelChartPainter(this.values, this.color);
  final Map<int, double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = values.values.fold(0.0, math.max);
    final barWidth = size.width / values.length;
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    var index = 0;
    for (final entry in values.entries) {
      final height = maxValue == 0
          ? 0.0
          : entry.value / maxValue * (size.height - 35);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          index * barWidth + 5,
          size.height - 24 - height,
          barWidth - 10,
          height,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: .82));
      text.text = TextSpan(
        text: '${entry.key}',
        style: TextStyle(fontSize: 10, color: color),
      );
      text.layout(maxWidth: barWidth);
      text.paint(canvas, Offset(index * barWidth, size.height - 18));
      index++;
    }
  }

  @override
  bool shouldRepaint(covariant _ChannelChartPainter old) =>
      old.values != values || old.color != color;
}
