import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/network_intelligence_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../widgets/related_tool_actions.dart';

class TlsInspectionPage extends StatefulWidget {
  const TlsInspectionPage({
    super.key,
    required this.appState,
    this.initialHost,
  });

  final AppState appState;
  final String? initialHost;

  @override
  State<TlsInspectionPage> createState() => _TlsInspectionPageState();
}

class _TlsInspectionPageState extends State<TlsInspectionPage> {
  final _host = TextEditingController(text: 'baidu.com');
  final _port = TextEditingController(text: '443');
  bool _running = false;
  bool _allowInvalidCertificate = false;
  TlsInspectionResult? _result;
  String? _error;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _host.addListener(_saveDraft);
    _port.addListener(_saveDraft);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    if (_draftLoaded) unawaited(_drafts.save('tool.tls', _draftValue()));
    _drafts.dispose();
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
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _allowInvalidCertificate,
          onChanged: _running
              ? null
              : (value) {
                  setState(() => _allowInvalidCertificate = value);
                  _saveDraft();
                },
          title: const LocalizedText('仅诊断：允许无效证书'),
          subtitle: const LocalizedText('仍会明确标记不可信，仅用于排查自签名或过期证书'),
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
          _valueCard('SHA-1 指纹', result.sha1Fingerprint, copyable: true),
          _valueCard('SHA-256 指纹', result.sha256Fingerprint, copyable: true),
          Card(
            child: ExpansionTile(
              title: const LocalizedText('PEM 证书'),
              subtitle: const LocalizedText('可复制并用于 openssl 等工具继续分析'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              trailing: IconButton(
                tooltip: context.tr('复制'),
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: result.certificatePem),
                ),
                icon: const Icon(Icons.copy_outlined),
              ),
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SelectableText(
                    result.certificatePem,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          RelatedToolActions(
            currentToolId: 'tls',
            appState: widget.appState,
            target: _host.text,
          ),
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
                !result.trusted || result.expired || result.notYetValid
                    ? Icons.error
                    : Icons.verified,
                color: !result.trusted || result.expired || result.notYetValid
                    ? const Color(0xFFD34D4D)
                    : const Color(0xFF168A5B),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LocalizedText(
                  !result.trusted
                      ? '系统信任验证未通过'
                      : result.notYetValid
                      ? '证书尚未生效'
                      : result.expired
                      ? '证书已过期'
                      : '系统信任链验证通过',
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
          LocalizedText(
            '${result.addressType == InternetAddressType.IPv6 ? 'IPv6' : 'IPv4'} · '
            '解析到 ${result.resolvedAddresses.length} 个地址',
          ),
          LocalizedText(
            'DNS ${result.dnsTime.inMilliseconds} ms · '
            'TCP ${result.connectTime.inMilliseconds} ms · '
            'TLS ${result.handshakeTime.inMilliseconds} ms · '
            '总计 ${result.totalTime.inMilliseconds} ms',
          ),
          Text(
            context.l10n.toolPages.tlsAlpnSummary(
              protocols: result.requestedProtocols.join(', '),
              derBytes: result.derLength,
            ),
          ),
          LocalizedText(
            '有效期 ${result.validFrom.toLocal()} → ${result.validTo.toLocal()}',
          ),
          LocalizedText(
            result.expired
                ? '已过期 ${-result.daysRemaining} 天'
                : '剩余 ${result.daysRemaining} 天',
          ),
          if (result.selfIssued) const LocalizedText('证书主题与签发者相同，可能为自签名证书'),
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
        allowInvalidCertificate: _allowInvalidCertificate,
      );
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '握手或证书验证失败：$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Map<String, Object?> _draftValue() => {
    'host': _host.text,
    'port': _port.text,
    'allowInvalidCertificate': _allowInvalidCertificate,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.tls');
    if (!mounted) return;
    if (draft != null) {
      _host.text = draft.payload['host']?.toString() ?? _host.text;
      _port.text = draft.payload['port']?.toString() ?? _port.text;
      _allowInvalidCertificate =
          draft.payload['allowInvalidCertificate'] == true;
    }
    final initialHost = widget.initialHost?.trim();
    if (initialHost != null && initialHost.isNotEmpty) _host.text = initialHost;
    _draftLoaded = true;
  }

  void _saveDraft() {
    if (_draftLoaded) _drafts.scheduleSave('tool.tls', _draftValue());
  }
}
