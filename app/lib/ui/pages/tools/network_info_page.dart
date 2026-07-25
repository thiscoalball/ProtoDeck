import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../models/network_context.dart';
import '../../../services/network_context_service.dart';

class NetworkInfoPage extends StatefulWidget {
  const NetworkInfoPage({super.key});

  @override
  State<NetworkInfoPage> createState() => _NetworkInfoPageState();
}

class _NetworkInfoPageState extends State<NetworkInfoPage> {
  late Future<NetworkContext> _future = _load();

  Future<NetworkContext> _load() async {
    // Serving-cell identity and granular radio measurements are protected by
    // Android's location permission. Denial still leaves basic network data.
    if (Platform.isAndroid) await Permission.locationWhenInUse.request();
    return NetworkContextService().load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('网络详情'),
      actions: [
        IconButton(
          onPressed: () => setState(() => _future = _load()),
          icon: const Icon(Icons.refresh),
          tooltip: context.tr('刷新'),
        ),
      ],
    ),
    body: FutureBuilder<NetworkContext>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _errorState(snapshot.error);
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _statusCard(data),
            const SizedBox(height: 18),
            _sectionTitle('网络与路由'),
            _dataCard([
              (
                '默认出口',
                data.usesVpn ? 'VPN（保留底层网络）' : data.transports.join(' / '),
              ),
              ('接口', data.interfaceName ?? '—'),
              (
                '本地地址',
                data.addresses
                    .map((a) => '${a.address}/${a.prefixLength}  ${a.family}')
                    .join('\n'),
              ),
              ('网关', data.gateways.join('\n')),
              ('DNS', data.dnsServers.join('\n')),
              ('MTU', '${data.mtu}'),
              ('计费网络', data.metered ? '是' : '否'),
              if (data.publicIpv4 != null) ('公网 IPv4（可选）', data.publicIpv4!),
              if (data.publicIpv6 != null) ('公网 IPv6（可选）', data.publicIpv6!),
            ]),
            if (data.adapters.isNotEmpty) ...[
              const SizedBox(height: 18),
              _sectionTitle('Windows 网络适配器'),
              ...data.adapters.map(_adapterCard),
            ],
            if (data.wifi != null) ...[
              const SizedBox(height: 18),
              _sectionTitle('Wi‑Fi 连接'),
              _wifiCard(data.wifi!),
            ],
            if (data.cellular != null) ...[
              const SizedBox(height: 18),
              _sectionTitle(
                data.transports.contains('cellular')
                    ? '蜂窝网络（当前承载）'
                    : '蜂窝网络（备用/底层接口）',
              ),
              _cellularCard(data.cellular!),
            ],
          ],
        );
      },
    ),
  );

  Widget _errorState(Object? error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.portable_wifi_off, size: 48),
          const SizedBox(height: 12),
          LocalizedText('读取失败：$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => setState(() => _future = _load()),
            child: const LocalizedText('重试'),
          ),
        ],
      ),
    ),
  );

  Widget _statusCard(NetworkContext data) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            data.validated ? Icons.cloud_done_outlined : Icons.lan_outlined,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                data.validated
                    ? '当前网络可访问互联网'
                    : data.connected
                    ? '已连接当前网络'
                    : '未连接网络',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              LocalizedText(
                data.usesVpn
                    ? '流量经由 VPN，下方保留底层 Wi‑Fi/蜂窝信息'
                    : data.transports.join(' / ').toUpperCase(),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: LocalizedText(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _wifiCard(WifiConnectionInfo wifi) => _dataCard([
    ('SSID', wifi.ssid ?? '—'),
    ('BSSID', wifi.bssid ?? '—'),
    ('信号', wifi.rssi == null ? '—' : '${wifi.rssi} dBm'),
    ('频率 / 信道', '${wifi.frequency ?? '—'} MHz  /  CH ${wifi.channel ?? '—'}'),
    ('Wi‑Fi 标准', wifi.standard ?? '—'),
    ('链路速率', '${wifi.linkSpeedMbps ?? '—'} Mbps'),
    (
      '收发速率',
      'RX ${wifi.rxLinkSpeedMbps ?? '—'} / TX ${wifi.txLinkSpeedMbps ?? '—'} Mbps',
    ),
  ]);

  Widget _adapterCard(NetworkAdapterInfo adapter) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                adapter.transport == 'wifi'
                    ? Icons.wifi_rounded
                    : adapter.transport == 'vpn'
                    ? Icons.vpn_key_outlined
                    : Icons.settings_ethernet_rounded,
                color: adapter.isDefault
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: LocalizedText(
                            adapter.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (adapter.isDefault) ...[
                          const SizedBox(width: 8),
                          const Chip(
                            label: LocalizedText('默认出口'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                    LocalizedText(
                      adapter.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (adapter.linkSpeed?.isNotEmpty == true)
                LocalizedText(
                  adapter.linkSpeed!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _adapterValue('类型', adapter.transport.toUpperCase()),
              _adapterValue('MTU', '${adapter.mtu}'),
              if (adapter.macAddress?.isNotEmpty == true)
                _adapterValue('MAC', adapter.macAddress!),
              for (final address in adapter.addresses)
                _adapterValue(
                  address.family,
                  '${address.address}/${address.prefixLength}',
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _adapterValue(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: LocalizedText(
      '$label  $value',
      style: const TextStyle(fontSize: 12.5),
    ),
  );

  Widget _cellularCard(CellularConnectionInfo cell) {
    final strength = _primaryCellStrength(cell);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  _cellIcon(cell.level),
                  size: 34,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        cell.operatorName ?? cell.simOperatorName ?? '蜂窝网络',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      LocalizedText(
                        '${cell.radioTechnology ?? '制式未知'} · ${_strengthLabel(strength)}${cell.roaming ? ' · 漫游' : ''}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (strength != null)
                  LocalizedText(
                    '$strength dBm',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          if (cell.metrics.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) => GridView.count(
                  crossAxisCount: constraints.maxWidth >= 520 ? 3 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.15,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: cell.metrics.entries
                      .map((entry) => _radioMetric(entry.key, entry.value))
                      .toList(),
                ),
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: LocalizedText('系统未提供详细无线指标。请开启位置服务并授予精确位置权限后刷新。'),
            ),
          const Divider(height: 1),
          ..._dataRows([
            ('运营商代码', cell.operatorCode ?? cell.simOperatorCode ?? '—'),
            ('注册状态', cell.registered ? '已注册当前小区' : '未确认'),
            ('邻区数量', '${cell.neighborCellCount}'),
            ...cell.identity.entries.map((entry) => (entry.key, entry.value)),
          ]),
        ],
      ),
    );
  }

  Widget _radioMetric(String name, int value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LocalizedText(
          _metricValue(name, value),
          maxLines: 1,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        LocalizedText(name, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  String _metricValue(String name, int value) {
    if (name.contains('RSRP') || name == 'RSSI' || name.contains('dBm')) {
      return '$value dBm';
    }
    if (name.contains('RSRQ') || name.contains('SINR') || name == 'RSSNR') {
      return '$value dB';
    }
    return '$value';
  }

  int? _primaryCellStrength(CellularConnectionInfo cell) =>
      cell.metrics['SS-RSRP'] ??
      cell.metrics['RSRP'] ??
      cell.metrics['CSI-RSRP'] ??
      cell.dbm;

  String _strengthLabel(int? value) {
    if (value == null) return '信号未知';
    if (value >= -80) return '信号极佳';
    if (value >= -90) return '信号良好';
    if (value >= -100) return '信号一般';
    if (value >= -110) return '信号较弱';
    return '信号很弱';
  }

  IconData _cellIcon(int? level) => switch (level) {
    4 => Icons.signal_cellular_4_bar,
    3 => Icons.signal_cellular_alt,
    2 => Icons.signal_cellular_alt_2_bar,
    1 => Icons.signal_cellular_alt_1_bar,
    _ => Icons.signal_cellular_connected_no_internet_0_bar,
  };

  Widget _dataCard(List<(String, String)> values) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(children: _dataRows(values)),
  );

  List<Widget> _dataRows(List<(String, String)> values) => [
    for (var index = 0; index < values.length; index++) ...[
      ListTile(
        title: LocalizedText(values[index].$1),
        subtitle: SelectableText(
          values[index].$2.isEmpty ? '—' : values[index].$2,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy_outlined, size: 20),
          tooltip: context.tr('复制'),
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: values[index].$2)),
        ),
      ),
      if (index != values.length - 1)
        const Divider(height: 1, indent: 16, endIndent: 16),
    ],
  ];
}
