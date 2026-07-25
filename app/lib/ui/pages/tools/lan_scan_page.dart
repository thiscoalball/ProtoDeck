import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/lan_scan_service.dart';
import '../../../services/network_defaults_service.dart';
import '../../../services/port_scan_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../../models/tool_route_args.dart';
import '../../tool_launcher.dart';
import '../remote/ssh_terminal_page.dart';

class LanScanPage extends StatefulWidget {
  const LanScanPage({super.key, required this.appState});
  final AppState appState;
  @override
  State<LanScanPage> createState() => _LanScanPageState();
}

class _LanScanPageState extends State<LanScanPage> {
  final _cidr = TextEditingController(text: '192.168.1.0/24');
  final _ports = TextEditingController(
    text: LanScanService.defaultPorts.join(','),
  );
  final _search = TextEditingController();
  LanScanCancellationToken? _token;
  StreamSubscription<LanScanProgress>? _subscription;
  LanScanProgress? _progress;
  String? _error;
  int _concurrency = 24;
  int _timeoutMs = 450;
  bool _includeMulticastDiscovery = true;
  _LanSort _sort = _LanSort.address;
  bool _onlyWithServices = false;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    for (final controller in [_cidr, _ports, _search]) {
      controller.addListener(_saveDraft);
    }
    unawaited(_restoreDraftAndDefaults());
  }

  @override
  void dispose() {
    _token?.cancel();
    _subscription?.cancel();
    if (_draftLoaded) unawaited(_drafts.save('tool.lan', _draftValue()));
    _drafts.dispose();
    _cidr.dispose();
    _ports.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('局域网扫描'),
        actions: [
          if (progress?.devices.isNotEmpty == true)
            IconButton(
              tooltip: context.tr('复制扫描结果'),
              onPressed: () => _copyResults(progress!),
              icon: const Icon(Icons.copy_all_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _cidr,
            enabled: progress?.running != true,
            decoration: const InputDecoration(
              label: LocalizedText('IPv4 子网（最大 /20）'),
            ),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const LocalizedText('扫描策略'),
            subtitle: Text(
              context.l10n.toolPages.lanScanStrategySummary(
                ports: _ports.text
                    .split(',')
                    .where((value) => value.trim().isNotEmpty)
                    .length,
                concurrency: _concurrency,
                timeoutMs: _timeoutMs,
              ),
            ),
            children: [
              TextField(
                controller: _ports,
                enabled: progress?.running != true,
                decoration: const InputDecoration(
                  label: LocalizedText('用于发现主机的 TCP 端口'),
                  helper: LocalizedText('开放或明确拒绝连接都可证明主机在线'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _concurrency,
                      decoration: const InputDecoration(
                        label: LocalizedText('并发数'),
                      ),
                      items: const [8, 16, 24, 32, 48]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(),
                      onChanged: progress?.running == true
                          ? null
                          : (value) {
                              setState(() => _concurrency = value ?? 24);
                              _saveDraft();
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _timeoutMs,
                      decoration: const InputDecoration(
                        label: LocalizedText('单端口超时'),
                      ),
                      items: const [250, 450, 750, 1000, 1500]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('$value ms'),
                            ),
                          )
                          .toList(),
                      onChanged: progress?.running == true
                          ? null
                          : (value) {
                              setState(() => _timeoutMs = value ?? 450);
                              _saveDraft();
                            },
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeMulticastDiscovery,
                onChanged: progress?.running == true
                    ? null
                    : (value) {
                        setState(() => _includeMulticastDiscovery = value);
                        _saveDraft();
                      },
                title: const LocalizedText('合并 SSDP / mDNS 发现'),
                subtitle: const LocalizedText('多播发现与 TCP 探测并行执行，并标记真实发现来源'),
              ),
              const SizedBox(height: 8),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: progress?.running == true ? null : _start,
                  icon: const Icon(Icons.radar),
                  label: const LocalizedText('开始扫描'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: progress?.running == true ? _stop : null,
                child: const LocalizedText('停止'),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress.total == 0
                  ? 0
                  : progress.completed / progress.total,
            ),
            LocalizedText(
              '${progress.completed}/${progress.total} · 发现 ${progress.devices.length} 台',
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: LocalizedText(_error!),
            ),
          const SizedBox(height: 12),
          if ((progress?.devices.isNotEmpty ?? false)) ...[
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                label: LocalizedText('搜索 IP、主机名或端口'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<_LanSort>(
                    initialValue: _sort,
                    decoration: const InputDecoration(
                      label: LocalizedText('排序方式'),
                      prefixIcon: Icon(Icons.sort_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _LanSort.address,
                        child: LocalizedText('IP 地址'),
                      ),
                      DropdownMenuItem(
                        value: _LanSort.hostname,
                        child: LocalizedText('主机名'),
                      ),
                      DropdownMenuItem(
                        value: _LanSort.services,
                        child: LocalizedText('开放服务数量'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _sort = value ?? _LanSort.address);
                      _saveDraft();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilterChip(
                  selected: _onlyWithServices,
                  label: const LocalizedText('仅有开放服务'),
                  onSelected: (value) {
                    setState(() => _onlyWithServices = value);
                    _saveDraft();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          ..._filteredDevices(progress).map(
            (device) => Card(
              child: ListTile(
                leading: const Icon(Icons.devices),
                title: LocalizedText(device.address),
                subtitle: LocalizedText(_deviceSubtitle(device)),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => _action(value, device.address),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'ping', child: LocalizedText('Ping')),
                    PopupMenuItem(value: 'ports', child: LocalizedText('端口检测')),
                    PopupMenuItem(value: 'http', child: LocalizedText('HTTP')),
                    PopupMenuItem(
                      value: 'telnet',
                      child: LocalizedText('Telnet :23'),
                    ),
                    PopupMenuItem(
                      value: 'ssh',
                      child: LocalizedText('SSH :22'),
                    ),
                    PopupMenuItem(
                      value: 'smb',
                      child: LocalizedText('SMB :445'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _start() {
    List<int> ports;
    try {
      ports = PortScanService().parsePorts(_ports.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    _token = LanScanCancellationToken();
    setState(() {
      _progress = null;
      _error = null;
    });
    _subscription = LanScanService()
        .scan(
          _cidr.text,
          ports: ports,
          concurrency: _concurrency,
          timeout: Duration(milliseconds: _timeoutMs),
          includeMulticastDiscovery: _includeMulticastDiscovery,
          token: _token,
        )
        .listen(
          (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onError: (Object error) {
            if (mounted) setState(() => _error = '$error');
          },
        );
  }

  void _stop() => _token?.cancel();

  List<LanDevice> _filteredDevices(LanScanProgress? progress) {
    final query = _search.text.trim().toLowerCase();
    final devices = (progress?.devices ?? const <LanDevice>[]).where((device) {
      if (_onlyWithServices && device.openPorts.isEmpty) return false;
      return query.isEmpty ||
          device.address.contains(query) ||
          (device.hostname?.toLowerCase().contains(query) ?? false) ||
          device.openPorts.any((port) => '$port'.contains(query));
    }).toList();
    devices.sort((left, right) {
      final result = switch (_sort) {
        _LanSort.address => _compareAddress(left.address, right.address),
        _LanSort.hostname => (left.hostname ?? '').toLowerCase().compareTo(
          (right.hostname ?? '').toLowerCase(),
        ),
        _LanSort.services => right.openPorts.length.compareTo(
          left.openPorts.length,
        ),
      };
      return result != 0
          ? result
          : _compareAddress(left.address, right.address);
    });
    return devices;
  }

  int _compareAddress(String left, String right) {
    try {
      final leftBytes = InternetAddress(left).rawAddress;
      final rightBytes = InternetAddress(right).rawAddress;
      for (var index = 0; index < leftBytes.length; index++) {
        final compared = leftBytes[index].compareTo(rightBytes[index]);
        if (compared != 0) return compared;
      }
    } on Object {
      // Fall through to lexical ordering for malformed discovery records.
    }
    return left.compareTo(right);
  }

  String _deviceSubtitle(LanDevice device) {
    final service = device.openPorts.isEmpty
        ? 'TCP 有响应，未发现开放端口'
        : '开放端口：${device.openPorts.join(', ')}';
    final methods = device.discoveryMethods.isEmpty
        ? ''
        : '\n发现方式：${device.discoveryMethods.join(' / ')}';
    return '${device.hostname ?? '未知主机'}\n$service$methods';
  }

  Map<String, Object?> _draftValue() => {
    'cidr': _cidr.text,
    'ports': _ports.text,
    'search': _search.text,
    'concurrency': _concurrency,
    'timeoutMs': _timeoutMs,
    'includeMulticastDiscovery': _includeMulticastDiscovery,
    'sort': _sort.name,
    'onlyWithServices': _onlyWithServices,
  };

  Future<void> _restoreDraftAndDefaults() async {
    final draft = await _drafts.load('tool.lan');
    if (!mounted) return;
    if (draft != null) {
      _cidr.text = draft.payload['cidr']?.toString() ?? _cidr.text;
      _ports.text = draft.payload['ports']?.toString() ?? _ports.text;
      _search.text = draft.payload['search']?.toString() ?? '';
      _concurrency =
          (draft.payload['concurrency'] as num?)?.toInt() ?? _concurrency;
      _timeoutMs = (draft.payload['timeoutMs'] as num?)?.toInt() ?? _timeoutMs;
      _includeMulticastDiscovery =
          draft.payload['includeMulticastDiscovery'] != false;
      _sort = _LanSort.values.firstWhere(
        (value) => value.name == draft.payload['sort'],
        orElse: () => _sort,
      );
      _onlyWithServices = draft.payload['onlyWithServices'] == true;
    } else {
      final defaults = await NetworkDefaultsService().load();
      if (mounted && defaults.subnet != null) _cidr.text = defaults.subnet!;
    }
    _draftLoaded = true;
    if (mounted) setState(() {});
  }

  void _saveDraft() {
    if (_draftLoaded) _drafts.scheduleSave('tool.lan', _draftValue());
  }

  Future<void> _copyResults(LanScanProgress progress) async {
    String cell(Object? value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';
    final devices = _filteredDevices(progress);
    final report = <String>[
      'ip,hostname,open_ports,discovery_methods',
      for (final device in devices)
        [
          cell(device.address),
          cell(device.hostname),
          cell(device.openPorts.join(' ')),
          cell(device.discoveryMethods.join(' ')),
        ].join(','),
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText('已复制 ${devices.length} 台设备的 CSV')),
      );
    }
  }

  void _action(String action, String host) {
    if ({'ping', 'ports', 'http', 'telnet', 'smb'}.contains(action)) {
      openTool(
        context,
        action,
        widget.appState,
        args: ToolRouteArgs(
          target: host,
          port: action == 'telnet'
              ? 23
              : action == 'smb'
              ? 445
              : null,
          sourceToolId: 'lan',
        ),
      );
    } else if (action == 'ssh') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              SshTerminalPage(appState: widget.appState, initialHost: host),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText('暂不支持操作：$action $host')));
    }
  }
}

enum _LanSort { address, hostname, services }
