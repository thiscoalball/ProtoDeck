import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../models/network_context.dart';
import '../../../services/native_network_service.dart';

enum _WifiBand { all, band24, band5, band6 }

double _channelWidthMHz(String value) {
  final match = RegExp(r'(20|40|80|160|320)').firstMatch(value);
  return double.tryParse(match?.group(1) ?? '') ?? 20;
}

class WifiAnalyzerPage extends StatefulWidget {
  const WifiAnalyzerPage({super.key});
  @override
  State<WifiAnalyzerPage> createState() => _WifiAnalyzerPageState();
}

class _WifiAnalyzerPageState extends State<WifiAnalyzerPage> {
  final _native = NativeNetworkService();
  final _search = TextEditingController();
  final _signalHistory = <int>[];
  List<WifiAccessPoint> _aps = [];
  NetworkContext? _context;
  Timer? _signalTimer;
  String _sort = 'signal';
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

  @override
  void initState() {
    super.initState();
    _load();
    _signalTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _sampleSignal(),
    );
  }

  @override
  void dispose() {
    _signalTimer?.cancel();
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
        _scanFresh = scan.fresh;
        _scanStatus = scan.status;
        _scanResultAge = scan.newestResultAge;
        _collectedAt = scan.newestResultAge == null
            ? scan.collectedAt
            : scan.collectedAt.subtract(scan.newestResultAge!);
        if (context.wifi?.rssi case final rssi?) _appendSignal(rssi);
        _sortRows();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Wi‑Fi'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: context.tr('重新扫描'),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.wifi), child: LocalizedText('当前连接')),
            Tab(icon: Icon(Icons.radar), child: LocalizedText('附近网络')),
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
              children: [_currentTab(), _nearbyTab(), _channelsTab()],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _currentTab() {
    final wifi = _context?.wifi;
    final ssid =
        _cleanSsid(wifi?.ssid) ?? _ssidFromScan(wifi?.bssid) ?? 'SSID 暂不可见';
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: LocalizedText(
                  '${rows.length} 个接入点 · ${_scanStatusLabel()}',
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
                ],
                onChanged: (value) => setState(() {
                  _sort = value!;
                  _sortRows();
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: LocalizedText('没有符合筛选条件的 Wi‑Fi'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final ap = rows[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        leading: _SignalGlyph(
                          rssi: ap.rssi,
                          color: _signalColor(ap.rssi),
                          size: 34,
                        ),
                        title: LocalizedText(
                          ap.ssid.isEmpty ? '<隐藏 SSID>' : ap.ssid,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: LocalizedText(
                          '${_bandName(ap.frequency)} · CH ${ap.channel} · ${ap.securityLabel}\n${ap.bssid}',
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            LocalizedText(
                              '${ap.rssi}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const LocalizedText('dBm'),
                          ],
                        ),
                        onTap: () => _showDetails(ap),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

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
        _recommendationCard(selectedBand, scores),
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
    final bands = channelMode
        ? const [_WifiBand.band24, _WifiBand.band5, _WifiBand.band6]
        : _WifiBand.values;
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
                  onSelected: (_) => setState(() => _band = band),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

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
      return matchesBand && matchesQuery;
    }).toList();
  }

  void _sortRows() {
    _aps.sort(
      (a, b) => switch (_sort) {
        'name' => a.ssid.compareTo(b.ssid),
        'channel' => a.channel.compareTo(b.channel),
        _ => b.rssi.compareTo(a.rssi),
      },
    );
  }

  void _showDetails(WifiAccessPoint ap) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                ],
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
              _detail('安全方式', ap.securityLabel),
              _detail(
                '采集时间',
                _collectedAt == null ? '—' : _collectedAt.toString(),
              ),
            ],
          ),
        ),
      ),
    );
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

  Widget _recommendationCard(_WifiBand band, Map<int, double> scores) {
    if (band == _WifiBand.band6) {
      return Card(
        color: const Color(0xFFFFF7E5),
        child: const ListTile(
          leading: Icon(Icons.info_outline, color: Color(0xFFD78500)),
          title: LocalizedText('CN 默认不推荐 6 GHz Wi‑Fi 信道'),
          subtitle: LocalizedText(
            '中国现行无线局域网频段为 2400–2483.5、5150–5350 和 5725–5850 MHz；6 GHz 扫描结果仅作观察。',
          ),
        ),
      );
    }
    final candidates = band == _WifiBand.band24
        ? const [1, 6, 11]
        : const [36, 40, 44, 48, 52, 56, 60, 64, 149, 153, 157, 161, 165];
    final ranked = [...candidates]
      ..sort((a, b) => (scores[a] ?? 0).compareTo(scores[b] ?? 0));
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
                  'CN 推荐信道',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...ranked.take(3).toList().asMap().entries.map((item) {
              final channel = item.value;
              final width = _cnMaxWidth(channel, band);
              final note =
                  band == _WifiBand.band5 && channel >= 52 && channel <= 64
                  ? ' · 仅限室内 · DFS/TPC'
                  : band == _WifiBand.band5 && channel <= 64
                  ? ' · 仅限室内'
                  : '';
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
                        '信道 $channel · 建议 ${band == _WifiBand.band24 ? 20 : width} MHz$note',
                      ),
                    ),
                    LocalizedText(
                      '拥挤 ${(scores[channel] ?? 0).toStringAsFixed(1)}',
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            LocalizedText(
              band == _WifiBand.band24
                  ? '2.4 GHz 法规频段最大可容纳 40 MHz；为降低相邻信道干扰，默认推荐 1/6/11 上的 20 MHz。'
                  : '最大可用频宽按 CN 连续频段估算：36–64 最多 160 MHz；149–161 最多 80 MHz；165 为 20 MHz。实际能力取决于路由器、终端和 DFS 环境。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  int _cnMaxWidth(int channel, _WifiBand band) {
    if (band == _WifiBand.band24) return 40;
    if (channel <= 64) return 160;
    if (channel <= 161) return 80;
    return 20;
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

extension on WifiAccessPoint {
  String get securityLabel {
    final value = security.toUpperCase();
    if (value.contains('WPA3') || value.contains('SAE')) return 'WPA3';
    if (value.contains('WPA2')) return 'WPA2';
    if (value.contains('WPA')) return 'WPA';
    if (value.contains('WEP')) return 'WEP';
    if (value.contains('OWE')) return 'OWE';
    return value.isEmpty || value == '[ESS]' ? '开放网络' : security;
  }
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
