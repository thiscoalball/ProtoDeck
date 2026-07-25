import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/local_discovery_service.dart';

class LocalDiscoveryPage extends StatefulWidget {
  const LocalDiscoveryPage({super.key});

  @override
  State<LocalDiscoveryPage> createState() => _LocalDiscoveryPageState();
}

class _LocalDiscoveryPageState extends State<LocalDiscoveryPage> {
  int _mode = 0;
  bool _running = false;
  List<SsdpDevice> _ssdp = const [];
  List<MdnsRecord> _mdns = const [];
  String? _error;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('局域网服务发现')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: LocalizedText('SSDP / UPnP'),
                icon: Icon(Icons.tv),
              ),
              ButtonSegment(
                value: 1,
                label: LocalizedText('mDNS / Bonjour'),
                icon: Icon(Icons.podcasts),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _running
                ? null
                : (value) => setState(() => _mode = value.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _running ? null : _scan,
              icon: const Icon(Icons.radar),
              label: LocalizedText(_mode == 0 ? '搜索 UPnP 设备' : '浏览 Bonjour 服务'),
            ),
          ),
        ),
        if (_running) const LinearProgressIndicator(),
        Expanded(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: LocalizedText(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _mode == 0
              ? _ssdpList()
              : _mdnsList(),
        ),
      ],
    ),
  );

  Widget _ssdpList() {
    if (!_running && _ssdp.isEmpty)
      return const Center(child: LocalizedText('尚未发现设备'));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _ssdp.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _ssdp[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.devices_other),
            title: LocalizedText(
              item.server ?? item.type ?? item.address,
              maxLines: 2,
            ),
            subtitle: LocalizedText(
              '${item.address}\n${item.location ?? item.usn ?? '无描述地址'}',
            ),
            isThreeLine: true,
            trailing: item.location == null
                ? null
                : IconButton(
                    tooltip: context.tr('复制描述地址'),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: item.location!)),
                    icon: const Icon(Icons.copy),
                  ),
          ),
        );
      },
    );
  }

  Widget _mdnsList() {
    if (!_running && _mdns.isEmpty)
      return const Center(child: LocalizedText('尚未发现服务记录'));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _mdns.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _mdns[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: LocalizedText(
                item.type,
                style: const TextStyle(fontSize: 10),
              ),
            ),
            title: LocalizedText(item.name),
            subtitle: SelectableText('${item.value}\nTTL ${item.ttl}s'),
          ),
        );
      },
    );
  }

  Future<void> _scan() async {
    setState(() {
      _running = true;
      _error = null;
      if (_mode == 0) _ssdp = const [];
      if (_mode == 1) _mdns = const [];
    });
    try {
      if (_mode == 0) {
        final result = await LocalDiscoveryService().discoverSsdp();
        if (mounted) setState(() => _ssdp = result);
      } else {
        final result = await LocalDiscoveryService().discoverMdns();
        if (mounted) setState(() => _mdns = result);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '发现失败：$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}
