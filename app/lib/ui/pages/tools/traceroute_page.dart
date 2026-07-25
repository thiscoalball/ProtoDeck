import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/geo_ip_service.dart';
import '../../../services/ip_tools_service.dart';
import '../../../services/native_network_service.dart';
import '../../../state/app_state.dart';
import '../../widgets/offline_geo_map.dart';

class _TraceRow {
  _TraceRow(this.hop, {this.geo});
  final NativeTraceHop hop;
  final GeoIpResult? geo;
}

class TraceroutePage extends StatefulWidget {
  const TraceroutePage({super.key, required this.appState});
  final AppState appState;
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
  @override
  void dispose() {
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
                    : (value) => setState(() => _resolveHostnames = value),
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
          ..._rows.map(
            (r) => Card(
              child: ListTile(
                leading: CircleAvatar(child: LocalizedText('${r.hop.hop}')),
                title: LocalizedText(
                  r.hop.timeout
                      ? '*  *  *'
                      : [
                          r.hop.hostname,
                          r.hop.address,
                        ].whereType<String>().join('  '),
                ),
                subtitle: LocalizedText(
                  '${r.hop.samplesMs.map((sample) => sample == null ? '*' : '${sample.toStringAsFixed(1)} ms').join('  ')}'
                  '${r.geo == null ? ' · 私网或位置未知' : ' · ${r.geo!.country} ${r.geo!.city}'}',
                ),
              ),
            ),
          ),
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
      for (final hop in hops) {
        GeoIpResult? geo;
        final address = hop.address;
        try {
          if (address != null && IpToolsService().classify(address).isPublic)
            geo = await _geo.lookup(address);
        } on Object {}
        if (!mounted) return;
        setState(() {
          _rows.add(_TraceRow(hop, geo: geo));
          _rows.sort((a, b) => a.hop.hop.compareTo(b.hop.hop));
        });
      }
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
}
