import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/local_discovery_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../../models/tool_route_args.dart';
import '../../tool_launcher.dart';

class LocalDiscoveryPage extends StatefulWidget {
  const LocalDiscoveryPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<LocalDiscoveryPage> createState() => _LocalDiscoveryPageState();
}

class _LocalDiscoveryPageState extends State<LocalDiscoveryPage> {
  int _mode = 0;
  final _filter = TextEditingController();
  final _ssdpTarget = TextEditingController(text: 'ssdp:all');
  final _mdnsQuery = TextEditingController(
    text: '_services._dns-sd._udp.local',
  );
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;
  int _durationSeconds = 4;
  bool _running = false;
  List<SsdpDevice> _ssdp = const [];
  List<MdnsRecord> _mdns = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    for (final controller in [_ssdpTarget, _mdnsQuery]) {
      controller.addListener(_saveDraft);
    }
    _filter.addListener(_onFilterChanged);
    _restoreDraft();
  }

  @override
  void dispose() {
    if (_draftLoaded) {
      unawaited(_drafts.save('tool.discovery', _draftValue()));
    }
    _drafts.dispose();
    _filter.dispose();
    _ssdpTarget.dispose();
    _mdnsQuery.dispose();
    super.dispose();
  }

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
                : (value) {
                    setState(() => _mode = value.first);
                    _saveDraft();
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _mode == 0 ? _ssdpTarget : _mdnsQuery,
                  enabled: !_running,
                  autocorrect: false,
                  decoration: InputDecoration(
                    label: LocalizedText(
                      _mode == 0 ? 'SSDP 搜索目标' : 'mDNS 服务类型',
                    ),
                    hintText: _mode == 0 ? 'ssdp:all' : '_http._tcp.local',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: _durationSeconds,
                items: const [
                  DropdownMenuItem(value: 2, child: Text('2s')),
                  DropdownMenuItem(value: 4, child: Text('4s')),
                  DropdownMenuItem(value: 8, child: Text('8s')),
                  DropdownMenuItem(value: 12, child: Text('12s')),
                ],
                onChanged: _running
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _durationSeconds = value);
                        _saveDraft();
                      },
              ),
            ],
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
        if ((_mode == 0 ? _ssdp : _mdns).isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              controller: _filter,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                label: LocalizedText('筛选发现结果'),
              ),
            ),
          ),
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
    final query = _filter.text.trim().toLowerCase();
    final rows = _ssdp
        .where((item) {
          if (query.isEmpty) return true;
          return [
            item.address,
            item.server,
            item.type,
            item.location,
            item.usn,
            ...item.headers.entries.map(
              (entry) => '${entry.key} ${entry.value}',
            ),
          ].whereType<String>().join(' ').toLowerCase().contains(query);
        })
        .toList(growable: false);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = rows[index];
        return Card(
          child: ListTile(
            onTap: () => _showSsdpDetails(item),
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
    final query = _filter.text.trim().toLowerCase();
    final rows = _mdns
        .where(
          (item) =>
              query.isEmpty ||
              '${item.name} ${item.type} ${item.value}'.toLowerCase().contains(
                query,
              ),
        )
        .toList(growable: false);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = rows[index];
        return Card(
          child: ListTile(
            onTap: () => _showMdnsDetails(item),
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
        final result = await LocalDiscoveryService().discoverSsdp(
          duration: Duration(seconds: _durationSeconds),
          searchTarget: _ssdpTarget.text.trim(),
        );
        if (mounted) setState(() => _ssdp = result);
      } else {
        final result = await LocalDiscoveryService().discoverMdns(
          duration: Duration(seconds: _durationSeconds),
          queryName: _mdnsQuery.text.trim(),
        );
        if (mounted) setState(() => _mdns = result);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '发现失败：$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _showSsdpDetails(SsdpDevice item) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          LocalizedText(
            item.server ?? item.type ?? item.address,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final entry in item.headers.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.key.toUpperCase()),
              subtitle: SelectableText(entry.value),
              trailing: IconButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: entry.value)),
                icon: const Icon(Icons.copy_outlined),
                tooltip: context.tr('复制'),
              ),
            ),
          if (item.location != null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                openTool(
                  this.context,
                  'http',
                  widget.appState,
                  args: ToolRouteArgs(
                    url: item.location,
                    sourceToolId: 'discovery',
                  ),
                );
              },
              icon: const Icon(Icons.http_rounded),
              label: const LocalizedText('诊断设备描述地址'),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _showMdnsDetails(MdnsRecord item) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              item.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SelectableText('${item.type}\n${item.value}\nTTL ${item.ttl}s'),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text:
                      '${item.name}\t${item.type}\t${item.value}\t${item.ttl}',
                ),
              ),
              icon: const Icon(Icons.copy_outlined),
              label: const LocalizedText('复制记录'),
            ),
          ],
        ),
      ),
    ),
  );

  Map<String, Object?> _draftValue() => {
    'mode': _mode,
    'duration': _durationSeconds,
    'ssdpTarget': _ssdpTarget.text,
    'mdnsQuery': _mdnsQuery.text,
    'filter': _filter.text,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.discovery');
    if (!mounted) return;
    final payload = draft?.payload;
    if (payload != null) {
      _mode = payload['mode'] == 1 ? 1 : 0;
      _durationSeconds = switch ((payload['duration'] as num?)?.toInt()) {
        2 => 2,
        8 => 8,
        12 => 12,
        _ => 4,
      };
      _ssdpTarget.text = payload['ssdpTarget']?.toString() ?? _ssdpTarget.text;
      _mdnsQuery.text = payload['mdnsQuery']?.toString() ?? _mdnsQuery.text;
      _filter.text = payload['filter']?.toString() ?? '';
    }
    _draftLoaded = true;
    setState(() {});
  }

  void _saveDraft() {
    if (_draftLoaded) {
      _drafts.scheduleSave('tool.discovery', _draftValue());
    }
  }

  void _onFilterChanged() {
    if (mounted) setState(() {});
    _saveDraft();
  }
}
