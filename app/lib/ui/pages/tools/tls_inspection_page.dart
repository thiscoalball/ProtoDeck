import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/network_intelligence_service.dart';

class TlsInspectionPage extends StatefulWidget {
  const TlsInspectionPage({super.key});

  @override
  State<TlsInspectionPage> createState() => _TlsInspectionPageState();
}

class _TlsInspectionPageState extends State<TlsInspectionPage> {
  final _host = TextEditingController(text: 'baidu.com');
  final _port = TextEditingController(text: '443');
  bool _running = false;
  TlsInspectionResult? _result;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('TLS 证书检查')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _host,
                enabled: !_running,
                decoration: const InputDecoration(
                  label: LocalizedText('域名或 IP'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _port,
                enabled: !_running,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(label: LocalizedText('端口')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: const Icon(Icons.verified_user_outlined),
          label: const LocalizedText('握手并验证证书'),
        ),
        if (_running) const LinearProgressIndicator(),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LocalizedText(_error!),
            ),
          ),
        ],
        if (_result case final result?) ...[
          const SizedBox(height: 14),
          _summaryCard(context, result),
          const SizedBox(height: 10),
          _valueCard('证书主题', result.subject),
          _valueCard('签发机构', result.issuer),
          _valueCard('SHA-256 指纹', result.sha256Fingerprint, copyable: true),
        ],
      ],
    ),
  );

  Widget _summaryCard(BuildContext context, TlsInspectionResult result) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.expired ? Icons.error : Icons.verified,
                color: result.expired
                    ? const Color(0xFFD34D4D)
                    : const Color(0xFF168A5B),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LocalizedText(
                  result.expired ? '证书已过期' : '系统信任链验证通过',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LocalizedText(
            '${result.address}:${result.port} · ${result.selectedProtocol ?? '未协商 ALPN'}',
          ),
          LocalizedText('TLS 握手 ${result.handshakeTime.inMilliseconds} ms'),
          LocalizedText(
            '有效期 ${result.validFrom.toLocal()} → ${result.validTo.toLocal()}',
          ),
          LocalizedText(
            result.expired
                ? '已过期 ${-result.daysRemaining} 天'
                : '剩余 ${result.daysRemaining} 天',
          ),
        ],
      ),
    ),
  );

  Widget _valueCard(String title, String value, {bool copyable = false}) =>
      Card(
        child: ListTile(
          title: LocalizedText(title),
          subtitle: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          trailing: copyable
              ? IconButton(
                  tooltip: context.tr('复制'),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: value)),
                  icon: const Icon(Icons.copy),
                )
              : null,
        ),
      );

  Future<void> _run() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = '端口范围应为 1～65535');
      return;
    }
    setState(() {
      _running = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await TlsInspectionService().inspect(
        _host.text,
        port: port,
      );
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '握手或证书验证失败：$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
}
