import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/dns_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../widgets/related_tool_actions.dart';

class DnsLookupPage extends StatefulWidget {
  const DnsLookupPage({super.key, required this.appState, this.initialHost});
  final AppState appState;
  final String? initialHost;

  @override
  State<DnsLookupPage> createState() => _DnsLookupPageState();
}

class _DnsLookupPageState extends State<DnsLookupPage> {
  final _host = TextEditingController(text: 'www.baidu.com');
  final _server = TextEditingController(text: '223.5.5.5');
  final _port = TextEditingController(text: '53');
  final _doh = TextEditingController(text: 'https://dns.alidns.com/dns-query');
  DnsRecordType _type = DnsRecordType.a;
  DnsTransport _transport = DnsTransport.udp;
  DnsLookupResult? _result;
  List<({String name, DnsLookupResult result})> _comparison = const [];
  bool _compareResolvers = false;
  bool _running = false;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    for (final controller in [_host, _server, _port, _doh]) {
      controller.addListener(_saveDraft);
    }
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.dns');
    if (!mounted) return;
    if (draft != null) {
      _host.text = draft.payload['host']?.toString() ?? _host.text;
      _server.text = draft.payload['server']?.toString() ?? _server.text;
      _port.text = draft.payload['port']?.toString() ?? _port.text;
      _doh.text = draft.payload['doh']?.toString() ?? _doh.text;
      setState(() {
        _type = DnsRecordType.values.firstWhere(
          (value) => value.name == draft.payload['type'],
          orElse: () => _type,
        );
        _transport = DnsTransport.values.firstWhere(
          (value) => value.name == draft.payload['transport'],
          orElse: () => _transport,
        );
        _compareResolvers = draft.payload['compareResolvers'] == true;
      });
    }
    final initialHost = widget.initialHost?.trim();
    if (initialHost != null && initialHost.isNotEmpty) _host.text = initialHost;
    _draftLoaded = true;
  }

  Map<String, Object?> _draftValue() => {
    'host': _host.text,
    'server': _server.text,
    'port': _port.text,
    'doh': _doh.text,
    'type': _type.name,
    'transport': _transport.name,
    'compareResolvers': _compareResolvers,
  };

  void _saveDraft() {
    if (_draftLoaded) _drafts.scheduleSave('tool.dns', _draftValue());
  }

  @override
  void dispose() {
    if (_draftLoaded) unawaited(_drafts.save('tool.dns', _draftValue()));
    _drafts.dispose();
    _host.dispose();
    _server.dispose();
    _port.dispose();
    _doh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('DNS 查询')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        TextField(
          controller: _host,
          enabled: !_running,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: context.tr(
              _type == DnsRecordType.ptr ? 'IP 地址或反向域名' : '域名',
            ),
            hintText: _type == DnsRecordType.ptr ? '8.8.8.8' : 'example.com',
          ),
          onSubmitted: (_) => _lookup(),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.dns_outlined),
              label: LocalizedText('单服务器'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.compare_arrows_rounded),
              label: LocalizedText('多 DNS 对比'),
            ),
          ],
          selected: {_compareResolvers},
          onSelectionChanged: _running
              ? null
              : (selection) {
                  setState(() {
                    _compareResolvers = selection.first;
                    _result = null;
                    _comparison = const [];
                  });
                  _saveDraft();
                },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<DnsRecordType>(
                initialValue: _type,
                decoration: const InputDecoration(label: LocalizedText('记录类型')),
                items: DnsRecordType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: LocalizedText(type.label),
                      ),
                    )
                    .toList(),
                onChanged: _running
                    ? null
                    : (value) {
                        setState(() => _type = value!);
                        _saveDraft();
                      },
              ),
            ),
            const SizedBox(width: 10),
            if (!_compareResolvers) ...[
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<DnsTransport>(
                  initialValue: _transport,
                  decoration: const InputDecoration(
                    label: LocalizedText('查询方式'),
                  ),
                  items: DnsTransport.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: LocalizedText(type.label),
                        ),
                      )
                      .toList(),
                  onChanged: _running
                      ? null
                      : (value) {
                          setState(() => _transport = value!);
                          _saveDraft();
                        },
                ),
              ),
            ],
          ],
        ),
        if (!_compareResolvers && _transport != DnsTransport.system) ...[
          const SizedBox(height: 12),
          if (_transport == DnsTransport.doh)
            TextField(
              controller: _doh,
              enabled: !_running,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'DoH Endpoint'),
            )
          else
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _server,
                    enabled: !_running,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      label: LocalizedText('DNS 服务器'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _port,
                    enabled: !_running,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr(
                        _transport == DnsTransport.dot ? '端口/853' : '端口',
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _running ? null : _lookup,
          icon: Icon(
            _compareResolvers ? Icons.compare_arrows_rounded : Icons.search,
          ),
          label: LocalizedText(
            _compareResolvers ? '对比公共 DNS' : '查询 ${_type.label}',
          ),
        ),
        if (_running) const LinearProgressIndicator(),
        if (_comparison.isNotEmpty) ...[
          const SizedBox(height: 16),
          _comparisonSummary(),
          const SizedBox(height: 10),
          ..._comparison.map(_resolverCard),
          const SizedBox(height: 12),
          RelatedToolActions(
            currentToolId: 'dns',
            appState: widget.appState,
            target: _host.text,
          ),
        ],
        if (_result case final result?) ...[
          const SizedBox(height: 16),
          _summary(result),
          const SizedBox(height: 10),
          if (result.records.isEmpty && result.error == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: LocalizedText('响应成功，但没有返回记录')),
              ),
            ),
          ...result.records.map(_recordCard),
          const SizedBox(height: 12),
          RelatedToolActions(
            currentToolId: 'dns',
            appState: widget.appState,
            target: _host.text,
          ),
        ],
      ],
    ),
  );

  Widget _summary(DnsLookupResult result) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.success ? Icons.check_circle : Icons.error_outline,
                color: result.success
                    ? const Color(0xFF168A5B)
                    : Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LocalizedText(
                  result.success ? '解析成功 · ${result.records.length} 条' : '解析失败',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              LocalizedText('${result.elapsed.inMilliseconds} ms'),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            '${context.tr('服务器')}: ${context.tr(result.server)}\n'
            '${context.tr('状态')}: ${result.rcode}',
          ),
          if (result.error != null) ...[
            const SizedBox(height: 6),
            LocalizedText(
              result.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _recordCard(DnsRecord record) => Card(
    child: ListTile(
      leading: Container(
        width: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: LocalizedText(
          record.type,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        ),
      ),
      title: SelectableText(record.data),
      subtitle: LocalizedText(
        '${record.name}\nTTL ${record.ttl}s · ${record.section}',
      ),
      isThreeLine: true,
      trailing: IconButton(
        onPressed: () => Clipboard.setData(ClipboardData(text: record.data)),
        icon: const Icon(Icons.copy_outlined),
        tooltip: context.tr('复制'),
      ),
    ),
  );

  Widget _comparisonSummary() {
    final successful = _comparison
        .where((item) => item.result.success)
        .toList();
    final answerGroups = <String, int>{};
    for (final item in successful) {
      final answers =
          item.result.records
              .where((record) => record.section == 'Answer')
              .map((record) => '${record.type}:${record.data}')
              .toList()
            ..sort();
      answerGroups.update(
        answers.join('|'),
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final consistent = successful.length > 1 && answerGroups.length == 1;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              consistent ? Icons.rule_rounded : Icons.warning_amber_rounded,
              color: consistent
                  ? const Color(0xFF168A5B)
                  : const Color(0xFFE48B2A),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(
                    consistent ? '解析结果一致' : '解析结果存在差异或失败',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.l10n.toolPages.dnsComparisonSummary(
                      successful: successful.length,
                      total: _comparison.length,
                      answerGroups: answerGroups.length,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resolverCard(({String name, DnsLookupResult result}) item) {
    final result = item.result;
    final answers = result.records
        .where((record) => record.section == 'Answer')
        .toList();
    return Card(
      child: ExpansionTile(
        leading: Icon(
          result.success ? Icons.check_circle_rounded : Icons.error_outline,
          color: result.success
              ? const Color(0xFF168A5B)
              : Theme.of(context).colorScheme.error,
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${context.tr(result.server)} · ${result.elapsed.inMilliseconds} ms · ${result.rcode}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (result.error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                result.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            )
          else if (answers.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: LocalizedText('没有 Answer 记录'),
            )
          else
            for (final record in answers)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: SelectableText(record.data),
                subtitle: Text('${record.type} · TTL ${record.ttl}s'),
                trailing: IconButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: record.data)),
                  tooltip: context.tr('复制'),
                  icon: const Icon(Icons.copy_outlined),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _lookup() async {
    final host = _host.text.trim();
    final port =
        int.tryParse(_port.text) ?? (_transport == DnsTransport.dot ? 853 : 53);
    if (host.isEmpty || port < 1 || port > 65535) return;
    setState(() {
      _running = true;
      _result = null;
      _comparison = const [];
    });
    if (_compareResolvers) {
      final resolvers = const [
        (name: 'AliDNS', server: '223.5.5.5'),
        (name: 'DNSPod', server: '119.29.29.29'),
        (name: 'Cloudflare', server: '1.1.1.1'),
        (name: 'Google', server: '8.8.8.8'),
      ];
      final results = await Future.wait([
        for (final resolver in resolvers)
          DnsService()
              .lookup(
                host,
                type: _type,
                transport: DnsTransport.udp,
                server: resolver.server,
                port: 53,
              )
              .then((result) => (name: resolver.name, result: result)),
      ]);
      if (mounted) {
        setState(() {
          _running = false;
          _comparison = results;
        });
      }
      return;
    }
    final result = await DnsService().lookup(
      host,
      type: _type,
      transport: _transport,
      server: _server.text.trim(),
      port: port,
      dohEndpoint: Uri.tryParse(_doh.text.trim()),
    );
    if (mounted) {
      setState(() {
        _running = false;
        _result = result;
      });
    }
  }
}
