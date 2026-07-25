import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/network_context.dart';
import '../../services/network_context_service.dart';
import '../../state/app_state.dart';
import '../../services/network_doctor_service.dart';
import '../tool_catalog.dart';
import '../tool_launcher.dart';
import '../widgets/page_header.dart';
import '../widgets/tool_tile.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.state,
    required this.onShowTools,
    required this.onShowSettings,
  });

  final AppState state;
  final VoidCallback onShowTools;
  final VoidCallback onShowSettings;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _networkService = NetworkContextService();
  final _signalHistory = <int>[];
  NetworkContext? _network;
  Timer? _signalTimer;
  StreamSubscription<NetworkDoctorProgress>? _doctorSubscription;
  NetworkDoctorCancellationToken? _doctorToken;
  final _healthSteps = <String, DoctorStepResult>{};
  DateTime? _lastHealthCheck;
  String? _networkSignature;
  String? _signalSource;
  bool _loading = true;
  bool _sampling = false;
  bool _healthRunning = false;

  @override
  void initState() {
    super.initState();
    _refreshNetwork();
    _signalTimer = Timer.periodic(
      defaultTargetPlatform == TargetPlatform.windows
          ? const Duration(seconds: 5)
          : const Duration(seconds: 2),
      (_) => _refreshNetwork(background: true),
    );
  }

  @override
  void dispose() {
    _signalTimer?.cancel();
    _doctorToken?.cancel();
    _doctorSubscription?.cancel();
    _networkService.close();
    super.dispose();
  }

  Future<void> _refreshNetwork({bool background = false}) async {
    if (_sampling) return;
    _sampling = true;
    if (!background && mounted) setState(() => _loading = true);
    try {
      final data = await _networkService.load(includePublicAddresses: false);
      if (!mounted) return;
      final signal = _signalReading(data);
      final signature = [
        ...data.transports,
        data.wifi?.ssid ?? '',
        data.gateways.firstOrNull ?? data.lanGateways.firstOrNull ?? '',
      ].join('|');
      final healthExpired =
          _lastHealthCheck == null ||
          DateTime.now().difference(_lastHealthCheck!) >
              const Duration(seconds: 45);
      final networkChanged = signature != _networkSignature;
      final shouldCheckHealth = !background || networkChanged || healthExpired;
      setState(() {
        _network = data;
        _loading = false;
        if (signal != null) {
          if (_signalSource != signal.source) {
            _signalHistory.clear();
            _signalSource = signal.source;
          }
          _signalHistory.add(signal.value);
          if (_signalHistory.length > 30) _signalHistory.removeAt(0);
        } else if (_signalSource != null) {
          _signalSource = null;
          _signalHistory.clear();
        }
      });
      if (shouldCheckHealth) {
        _networkSignature = signature;
        unawaited(_refreshHealth(clearPrevious: networkChanged));
      }
    } on Object {
      if (mounted && !background) setState(() => _loading = false);
    } finally {
      _sampling = false;
    }
  }

  Future<void> _refreshHealth({bool clearPrevious = false}) async {
    if (_healthRunning && !clearPrevious) return;
    _doctorToken?.cancel();
    await _doctorSubscription?.cancel();
    final token = NetworkDoctorCancellationToken();
    _doctorToken = token;
    _lastHealthCheck = DateTime.now();
    if (mounted) {
      setState(() {
        _healthRunning = true;
        if (clearPrevious) _healthSteps.clear();
      });
    }
    _doctorSubscription = NetworkDoctorService()
        .run(token: token)
        .listen(
          (progress) {
            if (!mounted) return;
            setState(() {
              for (final step in progress.steps) {
                _healthSteps[step.id] = step;
              }
              _healthRunning = progress.running;
            });
          },
          onError: (_) {
            if (mounted) setState(() => _healthRunning = false);
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.l10n.dashboard;
    final quickTools = toolCatalog
        .where(
          (item) => [
            'doctor',
            'ping',
            'lan',
            'wifi',
            'api_workbench',
          ].contains(item.id),
        )
        .toList();
    final featuredTools = toolCatalog
        .where(
          (item) => [
            'traceroute',
            'dns',
            'iperf',
            'bluetooth_debug',
          ].contains(item.id),
        )
        .toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'ProtoDeck',
            subtitle: strings.subtitle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _topConnectionStatus(context),
                const SizedBox(width: 7),
                IconButton(
                  onPressed: widget.onShowSettings,
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: context.l10n.common.settings,
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _networkCard(context)),
        SliverToBoxAdapter(child: _quickActionDeck(context, quickTools)),
        SliverToBoxAdapter(
          child: _sectionTitle(
            context,
            strings.exploreMore,
            action: widget.onShowTools,
            trailing: strings.allTools,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 152,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: featuredTools.length,
            itemBuilder: (context, index) => ToolTile(
              tool: featuredTools[index],
              compact: true,
              onTap: () =>
                  openTool(context, featuredTools[index].id, widget.state),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _networkCard(BuildContext context) {
    final strings = context.l10n.dashboard;
    final data = _network;
    final signal = data == null ? null : _signalReading(data);
    final quality = _networkQuality(data, signal);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1028446D),
              blurRadius: 30,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: LocalizedText(
                    _primaryNetworkName(data),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : _refreshNetwork,
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainer,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: context.l10n.common.refresh,
                ),
              ],
            ),
            LocalizedText(
              data == null ? strings.readingNetwork : _networkSummary(data),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            _heroMetrics(context, data, signal),
            const SizedBox(height: 10),
            if (data?.transports.contains('ethernet') == true && signal == null)
              _ethernetPanel(data!, quality)
            else
              _signalPanel(signal, quality),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => openTool(context, 'doctor', widget.state),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: LocalizedText(strings.oneTapDiagnosis),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => openTool(context, 'network', widget.state),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  tooltip: strings.networkDetails,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroMetrics(
    BuildContext context,
    NetworkContext? data,
    _SignalReading? signal,
  ) {
    final strings = context.l10n.dashboard;
    final ipv4 = data?.addresses
        .where((address) => address.family == 'IPv4')
        .map((address) => address.address)
        .firstOrNull;
    final showingWifi =
        signal?.isWifi == true ||
        (signal == null && data?.transports.contains('wifi') == true);
    final frequency = showingWifi ? data?.wifi?.frequency : null;
    final band = frequency == null
        ? (signal?.isWifi == false
              ? data?.cellular?.radioTechnology ?? strings.cellularNetwork
              : (data?.transports.contains('wifi') == true
                    ? 'Wi‑Fi'
                    : data?.transports.contains('ethernet') == true
                    ? strings.wiredNetwork
                    : data?.usesVpn == true
                    ? 'VPN'
                    : data?.cellular?.radioTechnology ??
                          strings.currentNetwork))
        : frequency >= 5925
        ? 'Wi‑Fi 6G'
        : frequency >= 4900
        ? 'Wi‑Fi 5G'
        : 'Wi‑Fi 2.4G';
    final gateway = data?.gateways.firstOrNull ?? data?.lanGateways.firstOrNull;
    final ethernet = data?.transports.contains('ethernet') == true;
    final linkSpeed = data?.defaultAdapter?.linkSpeed;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                key: const ValueKey('compact-signal-icon'),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: _compactSignalIcon(data, signal),
              ),
              const SizedBox(width: 10),
              Expanded(child: _infoText(strings.accessType, band)),
              _infoText(
                ethernet ? strings.linkSpeed : strings.signalStrength,
                ethernet
                    ? linkSpeed ?? '—'
                    : signal == null
                    ? '—'
                    : '${signal.value} dBm',
                alignEnd: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.smartphone_rounded,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(child: _inlineInfo(strings.localAddress, ipv4 ?? '—')),
              const SizedBox(width: 8),
              Icon(
                Icons.router_outlined,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(child: _inlineInfo(strings.gateway, gateway ?? '—')),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _healthStatusItem(
                  strings.network,
                  _healthSteps['interface'],
                ),
              ),
              Expanded(
                child: _healthStatusItem(
                  strings.gateway,
                  _healthSteps['gateway'],
                ),
              ),
              Expanded(child: _healthStatusItem('DNS', _healthSteps['dns'])),
              Expanded(
                child: _healthStatusItem(
                  strings.internet,
                  _healthSteps['internet'],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _healthStatusItem(String label, DoctorStepResult? step) {
    final (icon, color) = switch (step?.status) {
      DoctorStepStatus.passed => (
        Icons.check_circle_rounded,
        const Color(0xFF2FA778),
      ),
      DoctorStepStatus.warning => (
        Icons.warning_amber_rounded,
        const Color(0xFFE39A35),
      ),
      DoctorStepStatus.failed => (
        Icons.cancel_rounded,
        const Color(0xFFD95562),
      ),
      null => (
        _healthRunning ? Icons.more_horiz_rounded : Icons.remove_circle_outline,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: LocalizedText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoText(String label, String value, {bool alignEnd = false}) =>
      Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          LocalizedText(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
      );

  Widget _inlineInfo(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LocalizedText(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      LocalizedText(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 9,
        ),
      ),
    ],
  );

  Widget _topConnectionStatus(BuildContext context) {
    final connected = _network?.connected == true;
    final validated = _network?.validated == true;
    final dns = _healthSteps['dns']?.status;
    final internet = _healthSteps['internet']?.status;
    final hasFailure =
        dns == DoctorStepStatus.failed || internet == DoctorStepStatus.failed;
    final hasWarning =
        dns == DoctorStepStatus.warning || internet == DoctorStepStatus.warning;
    final color = hasFailure
        ? const Color(0xFFD95562)
        : hasWarning
        ? const Color(0xFFE39A35)
        : internet == DoctorStepStatus.passed
        ? const Color(0xFF2FA778)
        : connected
        ? const Color(0xFFE39A35)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final label = context.l10n.dashboard.connectionStatus(
      dnsStatus: dns?.name,
      internetStatus: internet?.name,
      running: _healthRunning,
      validated: validated,
      connected: connected,
      loading: _loading,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          LocalizedText(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionDeck(BuildContext context, List<ToolDefinition> tools) =>
      Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D28446D),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final tool in tools)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => openTool(context, tool.id, widget.state),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(tool.icon, size: 21, color: tool.color),
                        ),
                        const SizedBox(height: 7),
                        LocalizedText(
                          switch (tool.id) {
                            'doctor' => context.l10n.dashboard.diagnosis,
                            'lan' => context.l10n.dashboard.scan,
                            'wifi' => 'Wi‑Fi',
                            'api_workbench' => 'API',
                            _ =>
                              context.l10n.tools
                                  .resolve(
                                    id: tool.id,
                                    fallbackName: tool.name,
                                    fallbackDescription: tool.description,
                                  )
                                  .name,
                          },
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _sectionTitle(
    BuildContext context,
    String title, {
    String? trailing,
    VoidCallback? action,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 18, 10),
    child: Row(
      children: [
        Expanded(
          child: LocalizedText(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -.35,
            ),
          ),
        ),
        if (trailing != null)
          action == null
              ? LocalizedText(
                  trailing,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                )
              : TextButton(onPressed: action, child: LocalizedText(trailing)),
      ],
    ),
  );

  Widget _compactSignalIcon(NetworkContext? data, _SignalReading? signal) {
    final color = Theme.of(context).colorScheme.primary;
    final wifiLevel =
        data?.wifi?.signalLevel?.clamp(0, 4) ??
        (signal?.isWifi == true ? _wifiLevel(signal!.value) : 0);
    final cellularLevel = _cellularLevel(data?.cellular, signal);
    final isWifi =
        signal?.isWifi == true || (signal == null && data?.wifi != null);
    final isCellular =
        signal?.isWifi == false ||
        (signal == null && data?.cellular != null && !isWifi);
    return TweenAnimationBuilder<double>(
      key: ValueKey(
        isWifi
            ? 'wifi-signal-level-$wifiLevel'
            : 'cellular-signal-level-$cellularLevel',
      ),
      tween: Tween(begin: .88, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Semantics(
        image: true,
        label: isWifi
            ? context.l10n.dashboard.wifiBars(wifiLevel)
            : isCellular
            ? context.l10n.dashboard.cellularBars(cellularLevel)
            : context.l10n.dashboard.currentNetwork,
        child: Center(
          child: isWifi
              ? CustomPaint(
                  size: const Size(24, 20),
                  painter: _WifiStrengthPainter(wifiLevel, color),
                )
              : Icon(
                  isCellular
                      ? _cellularLevelIcon(cellularLevel)
                      : _networkIcon(data),
                  color: color,
                  size: 22,
                ),
        ),
      ),
    );
  }

  int _cellularLevel(CellularConnectionInfo? cellular, _SignalReading? signal) {
    final reported = cellular?.level;
    if (reported != null) return reported.clamp(0, 4);
    final value = signal?.isWifi == false ? signal?.value : cellular?.dbm;
    if (value == null) return 0;
    return switch (value) {
      >= -80 => 4,
      >= -90 => 3,
      >= -100 => 2,
      >= -110 => 1,
      _ => 0,
    };
  }

  IconData _cellularLevelIcon(int level) => switch (level) {
    4 => Icons.signal_cellular_4_bar,
    3 => Icons.signal_cellular_alt,
    2 => Icons.signal_cellular_alt_2_bar,
    1 => Icons.signal_cellular_alt_1_bar,
    _ => Icons.signal_cellular_connected_no_internet_0_bar,
  };

  Widget _signalPanel(_SignalReading? signal, _QualityAssessment quality) {
    final accent = quality.color;
    final strings = context.l10n.dashboard;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                signal?.isWifi == true
                    ? Icons.wifi_rounded
                    : Icons.signal_cellular_alt,
                size: 19,
                color: accent,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: LocalizedText(
                  signal == null
                      ? strings.signalStrength
                      : signal.isWifi
                      ? strings.wifiSignalStrength
                      : strings.cellularSignalStrength,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (signal != null)
                LocalizedText(
                  '${signal.value} dBm',
                  style: TextStyle(
                    color: accent,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: quality.color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: LocalizedText(
                  quality.label,
                  style: TextStyle(
                    color: quality.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 68,
            width: double.infinity,
            child: _signalHistory.isEmpty
                ? Center(
                    child: LocalizedText(
                      strings.waitingForSignal,
                      style: const TextStyle(
                        color: Color(0xFF668398),
                        fontSize: 12,
                      ),
                    ),
                  )
                : CustomPaint(
                    painter: _DashboardSignalPainter(
                      _signalHistory,
                      accent,
                      minimum: signal?.isWifi == true ? -100 : -120,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _ethernetPanel(NetworkContext data, _QualityAssessment quality) {
    final strings = context.l10n.dashboard;
    final adapter = data.defaultAdapter;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: quality.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.settings_ethernet_rounded,
              color: quality.color,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  strings.ethernetLink,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                LocalizedText(
                  adapter?.description.isNotEmpty == true
                      ? adapter!.description
                      : data.interfaceName ?? strings.wiredNetwork,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LocalizedText(
                adapter?.linkSpeed ?? '—',
                style: TextStyle(
                  color: quality.color,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              LocalizedText(
                '${data.adapters.length} ${strings.activeAdapters}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _wifiLevel(int rssi) => (((rssi + 100) / 15).ceil()).clamp(0, 4);

  _SignalReading? _signalReading(NetworkContext data) {
    final cellular = data.cellular;
    if (data.transports.contains('cellular') && cellular != null) {
      return _cellularSignal(cellular);
    }
    final wifiRssi = data.wifi?.rssi;
    if (wifiRssi != null && wifiRssi > -127) {
      return _SignalReading(
        source: 'wifi:${data.wifi?.bssid ?? ''}',
        label: 'Wi‑Fi RSSI',
        value: wifiRssi,
        isWifi: true,
      );
    }
    return cellular == null ? null : _cellularSignal(cellular);
  }

  _SignalReading? _cellularSignal(CellularConnectionInfo cell) {
    final metric = <(String, int?)>[
      ('5G SS‑RSRP', cell.metrics['SS-RSRP']),
      ('LTE RSRP', cell.metrics['RSRP']),
      ('5G CSI‑RSRP', cell.metrics['CSI-RSRP']),
      (context.l10n.dashboard.cellularSignal, cell.dbm),
    ].where((entry) => entry.$2 != null).firstOrNull;
    if (metric == null) return null;
    return _SignalReading(
      source: 'cellular:${cell.radioTechnology ?? ''}',
      label: metric.$1,
      value: metric.$2!,
      isWifi: false,
    );
  }

  _QualityAssessment _networkQuality(
    NetworkContext? data,
    _SignalReading? signal,
  ) {
    final strings = context.l10n.dashboard;
    if (data == null || !data.connected) {
      return _QualityAssessment(strings.disconnected, const Color(0xFF708090));
    }
    final dnsStatus = _healthSteps['dns']?.status;
    final internetStatus = _healthSteps['internet']?.status;
    if (dnsStatus == DoctorStepStatus.failed ||
        internetStatus == DoctorStepStatus.failed) {
      return _QualityAssessment(
        strings.networkProblem,
        const Color(0xFFD95562),
      );
    }
    if (dnsStatus == DoctorStepStatus.warning ||
        internetStatus == DoctorStepStatus.warning) {
      return _QualityAssessment(
        strings.limitedConnection,
        const Color(0xFFE39A35),
      );
    }
    if (signal == null) {
      return _QualityAssessment(
        data.validated ? strings.connectionNormal : strings.lanAvailable,
        data.validated ? const Color(0xFF168A5B) : const Color(0xFFCA7A16),
      );
    }
    final value = signal.value;
    final qualityIndex = signal.isWifi
        ? switch (value) {
            >= -55 => 4,
            >= -65 => 3,
            >= -75 => 2,
            >= -85 => 1,
            _ => 0,
          }
        : switch (value) {
            >= -80 => 4,
            >= -90 => 3,
            >= -100 => 2,
            >= -110 => 1,
            _ => 0,
          };
    final label = switch (qualityIndex) {
      4 => strings.excellent,
      3 => strings.good,
      2 => strings.fair,
      1 => strings.weak,
      _ => strings.veryWeak,
    };
    final color = switch (qualityIndex) {
      >= 3 => const Color(0xFF168A5B),
      2 => const Color(0xFFCA7A16),
      _ => const Color(0xFFD34D4D),
    };
    return _QualityAssessment(label, color);
  }

  IconData _networkIcon(NetworkContext? data) {
    if (data?.usesVpn == true) return Icons.vpn_lock_outlined;
    if (data?.transports.contains('wifi') == true) return Icons.wifi;
    if (data?.transports.contains('cellular') == true)
      return Icons.signal_cellular_alt;
    if (data?.transports.contains('ethernet') == true)
      return Icons.settings_ethernet;
    return Icons.route;
  }

  String _primaryNetworkName(NetworkContext? data) {
    final strings = context.l10n.dashboard;
    if (data == null) return strings.readingNetwork;
    if (data.transports.contains('cellular')) {
      final operatorName = data.cellular?.operatorName;
      return operatorName?.isNotEmpty == true
          ? operatorName!
          : strings.cellularNetwork;
    }
    final ssid = data.wifi?.ssid;
    if (ssid != null && ssid.isNotEmpty && ssid != '<unknown ssid>') {
      return ssid;
    }
    if (data.transports.contains('ethernet')) return strings.ethernet;
    if (data.usesVpn) return strings.vpnNetwork;
    return data.interfaceName ?? strings.currentNetwork;
  }

  String _networkSummary(NetworkContext data) {
    final strings = context.l10n.dashboard;
    final parts = <String>[
      if (data.transports.contains('wifi'))
        data.wifi?.standard?.isNotEmpty == true
            ? data.wifi!.standard!
            : strings.currentWifi,
      if (data.wifi?.channel != null) strings.channel(data.wifi!.channel!),
      if (data.transports.contains('cellular'))
        data.cellular?.radioTechnology ?? strings.cellularNetwork,
      if (data.transports.contains('ethernet')) strings.wiredNetwork,
      if (data.usesVpn) strings.vpnEnabled,
    ];
    return parts.isEmpty ? strings.currentNetwork : parts.join(' · ');
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _SignalReading {
  const _SignalReading({
    required this.source,
    required this.label,
    required this.value,
    required this.isWifi,
  });

  final String source;
  final String label;
  final int value;
  final bool isWifi;
}

class _QualityAssessment {
  const _QualityAssessment(this.label, this.color);

  final String label;
  final Color color;
}

class _DashboardSignalPainter extends CustomPainter {
  const _DashboardSignalPainter(
    this.values,
    this.color, {
    required this.minimum,
  });

  final List<int> values;
  final Color color;
  final int minimum;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 25.0;
    const top = 4.0;
    const bottomPadding = 12.0;
    final bottom = size.height - bottomPadding;
    final height = bottom - top;
    final width = size.width - left - 3;
    double yFor(int value) {
      final normalized = ((-value).clamp(0, -minimum)) / -minimum;
      return top + normalized * height;
    }

    final gridPaint = Paint()
      ..color = color.withValues(alpha: .13)
      ..strokeWidth = 1;
    final step = (-minimum / 4).round();
    for (final value in [0, -step, -step * 2, -step * 3, minimum]) {
      final y = yFor(value);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      final text = TextPainter(
        text: TextSpan(
          text: '$value',
          style: TextStyle(fontSize: 8, color: color.withValues(alpha: .65)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(0, y - 5));
    }
    if (values.isEmpty) return;

    final points = <Offset>[];
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = left + index / math.max(1, values.length - 1) * width;
      final point = Offset(x, yFor(values[index]));
      points.add(point);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    final area = Path.from(path)
      ..lineTo(points.last.dx, bottom)
      ..lineTo(points.first.dx, bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: .015)],
        ).createShader(Rect.fromLTRB(left, top, size.width, bottom)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final latest = points.last;
    canvas.drawCircle(latest, 5, Paint()..color = color.withValues(alpha: .18));
    canvas.drawCircle(latest, 2.7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DashboardSignalPainter oldDelegate) => true;
}

class _WifiStrengthPainter extends CustomPainter {
  const _WifiStrengthPainter(this.level, this.color);

  final int level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 3);
    for (var index = 0; index < 3; index++) {
      final active = level >= index + 2;
      final radius = 6.0 + index * 5.2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi * 1.25,
        math.pi * .5,
        false,
        Paint()
          ..color = color.withValues(alpha: active ? 1 : .28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(
      center,
      2.3,
      Paint()..color = color.withValues(alpha: level > 0 ? 1 : .28),
    );
  }

  @override
  bool shouldRepaint(covariant _WifiStrengthPainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.color != color;
}
