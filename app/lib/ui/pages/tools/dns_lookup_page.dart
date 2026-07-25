import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/dns_service.dart';
import '../../../state/app_state.dart';

class DnsLookupPage extends StatefulWidget {
  const DnsLookupPage({super.key, required this.appState});
  final AppState appState;

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
  bool _running = false;

  @override
  void dispose() {
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
                    : (value) => setState(() => _type = value!),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<DnsTransport>(
                initialValue: _transport,
                decoration: const InputDecoration(label: LocalizedText('查询方式')),
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
                    : (value) => setState(() => _transport = value!),
              ),
            ),
          ],
        ),
        if (_transport != DnsTransport.system) ...[
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
                      labelText: _transport == DnsTransport.dot
                          ? '端口/853'
                          : '端口',
                    ),
                  ),
                ),
              ],
            ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _running ? null : _lookup,
          icon: const Icon(Icons.search),
          label: LocalizedText('查询 ${_type.label}'),
        ),
        if (_running) const LinearProgressIndicator(),
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
            '${context.tr('服务器')}：${result.server}\n'
            '${context.tr('状态')}：${result.rcode}',
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

  Future<void> _lookup() async {
    final host = _host.text.trim();
    final port =
        int.tryParse(_port.text) ?? (_transport == DnsTransport.dot ? 853 : 53);
    if (host.isEmpty || port < 1 || port > 65535) return;
    setState(() {
      _running = true;
      _result = null;
    });
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
