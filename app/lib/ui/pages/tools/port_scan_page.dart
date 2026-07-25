import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/port_scan_service.dart';
import '../../../services/network_defaults_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../widgets/related_tool_actions.dart';

class PortScanPage extends StatefulWidget {
  const PortScanPage({
    super.key,
    required this.appState,
    this.initialHost,
    this.initialPort,
  });
  final AppState appState;
  final String? initialHost;
  final int? initialPort;

  @override
  State<PortScanPage> createState() => _PortScanPageState();
}

class _PortScanPageState extends State<PortScanPage> {
  final _host = TextEditingController(text: '192.168.1.1');
  final _ports = TextEditingController(text: '22,53,80,443,8080');
  final _timeout = TextEditingController(text: '900');
  final _concurrency = TextEditingController(text: '20');
  final _service = PortScanService();
  final _results = <PortScanResult>[];
  CancellationToken? _token;
  StreamSubscription<PortScanResult>? _subscription;
  bool _running = false;
  bool _grabBanner = false;
  String _addressFamily = 'auto';
  _PortResultFilter _filter = _PortResultFilter.all;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _host.addListener(_saveDraft);
    _ports.addListener(_saveDraft);
    _timeout.addListener(_saveDraft);
    _concurrency.addListener(_saveDraft);
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.port_scan');
    if (!mounted) return;
    if (draft != null) {
      _host.text = draft.payload['host']?.toString() ?? _host.text;
      _ports.text = draft.payload['ports']?.toString() ?? _ports.text;
      _timeout.text = draft.payload['timeout']?.toString() ?? _timeout.text;
      _concurrency.text =
          draft.payload['concurrency']?.toString() ?? _concurrency.text;
      _grabBanner = draft.payload['grabBanner'] == true;
      _addressFamily =
          draft.payload['addressFamily']?.toString() ?? _addressFamily;
      _filter = _PortResultFilter.values.firstWhere(
        (value) => value.name == draft.payload['filter'],
        orElse: () => _filter,
      );
    } else {
      final defaults = await NetworkDefaultsService().load();
      if (mounted && defaults.gateway != null) _host.text = defaults.gateway!;
    }
    final initialHost = widget.initialHost?.trim();
    if (initialHost != null && initialHost.isNotEmpty) _host.text = initialHost;
    if (widget.initialPort != null) _ports.text = '${widget.initialPort}';
    _draftLoaded = true;
  }

  Map<String, Object?> _draftValue() => {
    'host': _host.text,
    'ports': _ports.text,
    'timeout': _timeout.text,
    'concurrency': _concurrency.text,
    'grabBanner': _grabBanner,
    'addressFamily': _addressFamily,
    'filter': _filter.name,
  };

  void _saveDraft() {
    if (_draftLoaded) {
      _drafts.scheduleSave('tool.port_scan', _draftValue());
    }
  }

  int _total = 0;

  @override
  void dispose() {
    _token?.cancel();
    _subscription?.cancel();
    if (_draftLoaded) {
      unawaited(_drafts.save('tool.port_scan', _draftValue()));
    }
    _drafts.dispose();
    _host.dispose();
    _ports.dispose();
    _timeout.dispose();
    _concurrency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = _results.where((item) => item.state == PortState.open).length;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('端口检测'),
        actions: [
          if (_results.isNotEmpty)
            IconButton(
              tooltip: context.tr('复制扫描结果'),
              onPressed: _copyResults,
              icon: const Icon(Icons.copy_all_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _host,
            enabled: !_running,
            decoration: const InputDecoration(label: LocalizedText('目标域名或 IP')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ports,
            enabled: !_running,
            decoration: const InputDecoration(
              label: LocalizedText('端口'),
              hint: LocalizedText('22,80,443 或 8000-8010'),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const LocalizedText('Web'),
                onPressed: _running
                    ? null
                    : () => _ports.text = '80,443,8080,8443',
              ),
              ActionChip(
                label: const LocalizedText('远程'),
                onPressed: _running
                    ? null
                    : () => _ports.text = '22,23,3389,5900',
              ),
              ActionChip(
                label: const LocalizedText('常用'),
                onPressed: _running
                    ? null
                    : () => _ports.text =
                          '21,22,25,53,80,110,143,443,445,3306,3389,5432,8080',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.tune_rounded),
              title: const LocalizedText('扫描参数'),
              subtitle: LocalizedText(
                '${_addressFamily.toUpperCase()} · ${_concurrency.text} 并发 · ${_timeout.text} ms${_grabBanner ? ' · Banner' : ''}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              children: [
                Row(
                  children: [
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _concurrency,
                        enabled: !_running,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          label: LocalizedText('并发数（1～100）'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _addressFamily,
                  decoration: const InputDecoration(
                    label: LocalizedText('地址族'),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'auto',
                      child: LocalizedText('自动选择'),
                    ),
                    DropdownMenuItem(value: 'ipv4', child: Text('IPv4')),
                    DropdownMenuItem(value: 'ipv6', child: Text('IPv6')),
                  ],
                  onChanged: _running
                      ? null
                      : (value) => setState(() {
                          _addressFamily = value ?? 'auto';
                          _saveDraft();
                        }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _grabBanner,
                  onChanged: _running
                      ? null
                      : (value) => setState(() {
                          _grabBanner = value;
                          _saveDraft();
                        }),
                  title: const LocalizedText('读取服务 Banner'),
                  subtitle: const LocalizedText(
                    '开放后最多读取 768 字节；常见 HTTP 端口发送 HEAD 请求',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : _start,
                  icon: const Icon(Icons.radar),
                  label: const LocalizedText('开始检测'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _running ? _stop : null,
                child: const LocalizedText('停止'),
              ),
            ],
          ),
          if (_running)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(
                value: _total == 0 ? null : _results.length / _total,
              ),
            ),
          if (_results.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metric('已完成', '${_results.length}/$_total'),
                    _metric('开放', '$open'),
                    _metric('未开放', '${_results.length - open}'),
                  ],
                ),
              ),
            ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 10),
            SegmentedButton<_PortResultFilter>(
              segments: [
                ButtonSegment(
                  value: _PortResultFilter.all,
                  label: LocalizedText('全部 ${_results.length}'),
                ),
                ButtonSegment(
                  value: _PortResultFilter.open,
                  label: LocalizedText('开放 $open'),
                ),
                ButtonSegment(
                  value: _PortResultFilter.attention,
                  label: LocalizedText(
                    '异常 ${_results.where((item) => item.state == PortState.filtered || item.state == PortState.unreachable).length}',
                  ),
                ),
              ],
              selected: {_filter},
              showSelectedIcon: false,
              onSelectionChanged: (values) {
                setState(() => _filter = values.first);
                _saveDraft();
              },
            ),
          ],
          const SizedBox(height: 8),
          ...(_visibleResults()..sort((left, right) {
                final openOrder = (left.state == PortState.open ? 0 : 1)
                    .compareTo(right.state == PortState.open ? 0 : 1);
                return openOrder != 0
                    ? openOrder
                    : left.port.compareTo(right.port);
              }))
              .map(
                (item) => Card(
                  child: ListTile(
                    leading: Icon(
                      item.state == PortState.open
                          ? Icons.lock_open
                          : item.state == PortState.filtered
                          ? Icons.filter_alt_outlined
                          : item.state == PortState.unreachable
                          ? Icons.signal_wifi_connected_no_internet_4_outlined
                          : Icons.lock_outline,
                      color: item.state == PortState.open
                          ? Colors.green
                          : Theme.of(context).colorScheme.outline,
                    ),
                    title: LocalizedText(
                      '${item.port} / ${_serviceName(item.port, item.banner)}',
                    ),
                    subtitle: LocalizedText(
                      '${item.address} · ${item.elapsed.inMilliseconds} ms'
                      '${item.banner?.isNotEmpty == true ? '\n${item.banner}' : ''}',
                      maxLines: item.banner == null ? 1 : 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: LocalizedText(
                      item.state.name.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: item.state == PortState.open
                            ? Colors.green
                            : null,
                      ),
                    ),
                    onTap: item.state == PortState.open
                        ? () => _showOpenPort(item)
                        : null,
                  ),
                ),
              ),
          const SizedBox(height: 12),
          LocalizedText(
            '仅对自己拥有或已获授权的设备进行扫描。一次最多 256 个端口。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
    children: [
      LocalizedText(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      LocalizedText(label),
    ],
  );

  void _start() {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    List<int> ports;
    try {
      ports = _service.parsePorts(_ports.text);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText(error.message)));
      return;
    }
    final timeout = int.tryParse(_timeout.text);
    final concurrency = int.tryParse(_concurrency.text);
    if (timeout == null || timeout < 100 || timeout > 30000) {
      _showError('超时必须为 100～30000 ms');
      return;
    }
    if (concurrency == null || concurrency < 1 || concurrency > 100) {
      _showError('并发数必须为 1～100');
      return;
    }
    _results.clear();
    _total = ports.length;
    _token = CancellationToken();
    setState(() => _running = true);
    _subscription = _service
        .scan(
          host: host,
          ports: ports,
          timeout: Duration(milliseconds: timeout),
          token: _token!,
          concurrency: concurrency,
          grabBanner: _grabBanner,
          addressType: switch (_addressFamily) {
            'ipv4' => InternetAddressType.IPv4,
            'ipv6' => InternetAddressType.IPv6,
            _ => null,
          },
        )
        .listen(
          (result) => setState(() => _results.add(result)),
          onDone: _finish,
          onError: (Object error) {
            if (mounted) {
              _showError('扫描失败：$error');
              setState(() => _running = false);
            }
          },
        );
  }

  Future<void> _finish() async {
    if (!mounted) return;
    setState(() => _running = false);
    final openPorts = _results
        .where((item) => item.state == PortState.open)
        .map((item) => item.port)
        .toList();
    final detail = _results
        .map((item) => '${item.port} ${item.state.name.toUpperCase()}')
        .join('\n');
    await widget.appState.addHistory(
      tool: 'port_scan',
      title: '端口检测 ${_host.text}',
      summary: openPorts.isEmpty ? '未发现开放端口' : '开放：${openPorts.join(', ')}',
      detail: detail,
      success: true,
    );
  }

  void _stop() {
    _token?.cancel();
    _subscription?.cancel();
    setState(() => _running = false);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: LocalizedText(message)));
  }

  List<PortScanResult> _visibleResults() => _results.where((item) {
    return switch (_filter) {
      _PortResultFilter.all => true,
      _PortResultFilter.open => item.state == PortState.open,
      _PortResultFilter.attention =>
        item.state == PortState.filtered || item.state == PortState.unreachable,
    };
  }).toList();

  Future<void> _copyResults() async {
    String cell(Object? value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';
    final report = <String>[
      'host,address,port,state,service,elapsed_ms,banner',
      for (final item in _visibleResults())
        [
          cell(_host.text.trim()),
          cell(item.address),
          item.port,
          item.state.name,
          cell(_serviceName(item.port, item.banner)),
          item.elapsed.inMilliseconds,
          cell(item.banner),
        ].join(','),
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('已复制 ${_visibleResults().length} 条端口结果的 CSV'),
        ),
      );
    }
  }

  Future<void> _showOpenPort(PortScanResult result) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LocalizedText(
                  '${_host.text}:${result.port} · OPEN',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (result.banner case final banner?) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    banner,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
                const SizedBox(height: 14),
                RelatedToolActions(
                  currentToolId: 'ports',
                  appState: widget.appState,
                  target: _host.text,
                  port: result.port,
                  toolIds: const ['ping', 'telnet', 'tls', 'http'],
                ),
              ],
            ),
          ),
        ),
      );

  String _serviceName(int port, String? banner) {
    final text = banner ?? '';
    if (text.startsWith('SSH-')) return text.split(RegExp(r'[\r\n]')).first;
    if (text.startsWith('HTTP/')) {
      final server = RegExp(
        r'^Server:\s*(.+)$',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(text)?.group(1)?.trim();
      return server == null ? 'HTTP' : 'HTTP · $server';
    }
    if (text.startsWith('220')) {
      if (port == 21) return 'FTP · ${text.split(RegExp(r'[\r\n]')).first}';
      if ({25, 465, 587}.contains(port)) return 'SMTP';
    }
    return const {
          21: 'FTP',
          22: 'SSH',
          25: 'SMTP',
          53: 'DNS',
          80: 'HTTP',
          110: 'POP3',
          143: 'IMAP',
          443: 'HTTPS',
          445: 'SMB',
          3306: 'MySQL',
          3389: 'RDP',
          5432: 'PostgreSQL',
          5900: 'VNC',
          6379: 'Redis',
          8080: 'HTTP-alt',
        }[port] ??
        'Unknown';
  }
}

enum _PortResultFilter { all, open, attention }
