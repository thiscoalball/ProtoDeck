import 'dart:async';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/geo_ip_service.dart';
import '../../../state/app_state.dart';
import '../../widgets/offline_geo_map.dart';

class GeoIpPage extends StatefulWidget {
  const GeoIpPage({super.key, required this.appState});
  final AppState appState;
  @override
  State<GeoIpPage> createState() => _GeoIpPageState();
}

class _GeoIpPageState extends State<GeoIpPage> {
  late final GeoIpService _service = GeoIpService(
    database: widget.appState.database,
  );
  final _input = TextEditingController(text: '1.1.1.1');
  bool _batch = false, _running = false;
  GeoCancellationToken? _token;
  StreamSubscription<GeoBatchProgress>? _sub;
  List<GeoIpResult> _results = [];
  String _status = '';
  @override
  void dispose() {
    _token?.cancel();
    _sub?.cancel();
    _service.close();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = _results
        .where((r) => r.success && r.latitude != null && r.longitude != null)
        .map(
          (r) => GeoMapPoint(
            latitude: r.latitude!,
            longitude: r.longitude!,
            label: r.city.isEmpty ? r.country : r.city,
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('IP 地理位置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: LocalizedText('单条')),
              ButtonSegment(value: true, label: LocalizedText('批量')),
            ],
            selected: {_batch},
            onSelectionChanged: _running
                ? null
                : (v) => setState(() => _batch = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            minLines: _batch ? 6 : 1,
            maxLines: 12,
            decoration: InputDecoration(
              labelText: context.tr(_batch ? '每行一个 IP 或域名' : 'IP 或域名'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: const Icon(Icons.public),
                  label: const LocalizedText('查询'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _running ? _stop : null,
                child: const LocalizedText('停止'),
              ),
            ],
          ),
          if (_running) const LinearProgressIndicator(),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: LocalizedText(_status),
            ),
          if (points.isNotEmpty) ...[
            OfflineGeoMap(points: points),
            const SizedBox(height: 10),
          ],
          ..._results.map(
            (r) => Card(
              child: ListTile(
                leading: Icon(
                  r.success ? Icons.location_on : Icons.info_outline,
                ),
                title: LocalizedText('${r.query}  ${r.ip}'),
                subtitle: LocalizedText(
                  r.error ??
                      '${r.country} ${r.region} ${r.city}\n${r.isp} · ${r.timezone}\n${r.latitude ?? '-'}, ${r.longitude ?? '-'}${r.cached ? ' · 7 日缓存' : ''}',
                ),
                isThreeLine: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results = [];
      _status = '';
    });
    if (!_batch) {
      try {
        final r = await _service.lookup(_input.text);
        setState(() => _results = [r]);
      } on Object catch (e) {
        setState(() => _status = '错误：$e');
      } finally {
        if (mounted) setState(() => _running = false);
      }
      return;
    }
    _token = GeoCancellationToken();
    _sub = _service
        .lookupBatch(_input.text.split('\n'), token: _token)
        .listen(
          (p) {
            if (mounted)
              setState(() {
                _results = p.results;
                _status =
                    '${p.completed}/${p.total} · 成功 ${p.successes} · 失败 ${p.failures}';
                _running = p.running;
              });
          },
          onDone: () {
            if (mounted) setState(() => _running = false);
          },
          onError: (Object e) {
            if (mounted)
              setState(() {
                _running = false;
                _status = '错误：$e';
              });
          },
        );
  }

  void _stop() {
    _token?.cancel();
    setState(() => _running = false);
  }
}
