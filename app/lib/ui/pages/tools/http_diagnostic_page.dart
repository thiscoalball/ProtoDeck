import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../models/structured_payload.dart';
import '../../../services/http_diagnostic_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../widgets/structured_data_viewer.dart';

class HttpDiagnosticPage extends StatefulWidget {
  const HttpDiagnosticPage({
    super.key,
    required this.appState,
    this.initialUrl,
  });
  final AppState appState;
  final String? initialUrl;
  @override
  State<HttpDiagnosticPage> createState() => _HttpDiagnosticPageState();
}

class _HttpDiagnosticPageState extends State<HttpDiagnosticPage> {
  late final _url = TextEditingController(
    text: widget.initialUrl ?? 'https://example.com',
  );
  final _body = TextEditingController();
  final _headers = TextEditingController();
  final _timeout = TextEditingController(text: '15');
  String _method = 'GET', _output = '';
  HttpDiagnosticResult? _result;
  bool _running = false;
  bool _followRedirects = true;
  int _maxBodyBytes = 1024 * 1024;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _url.addListener(_saveDraft);
    _timeout.addListener(_saveDraft);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    if (_draftLoaded) unawaited(_drafts.save('tool.http', _draftValue()));
    _drafts.dispose();
    _url.dispose();
    _body.dispose();
    _headers.dispose();
    _timeout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('HTTP 诊断')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            SizedBox(
              width: 105,
              child: DropdownButtonFormField<String>(
                initialValue: _method,
                items:
                    const [
                          'GET',
                          'HEAD',
                          'POST',
                          'PUT',
                          'PATCH',
                          'DELETE',
                          'OPTIONS',
                        ]
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: LocalizedText(v),
                          ),
                        )
                        .toList(),
                onChanged: (v) {
                  setState(() => _method = v!);
                  _saveDraft();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _url,
                decoration: const InputDecoration(labelText: 'URL'),
              ),
            ),
          ],
        ),
        if (_method == 'POST' || _method == 'PUT' || _method == 'PATCH') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(label: LocalizedText('请求正文')),
          ),
        ],
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const LocalizedText('请求头与高级选项'),
          children: [
            TextField(
              controller: _headers,
              enabled: !_running,
              minLines: 2,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                label: LocalizedText('请求头（每行一个）'),
                hintText: 'Accept: application/json',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _followRedirects,
              title: const LocalizedText('自动跟随重定向'),
              subtitle: const LocalizedText('最多跟随 5 次，并保留重定向链'),
              onChanged: _running
                  ? null
                  : (value) {
                      setState(() => _followRedirects = value);
                      _saveDraft();
                    },
            ),
            DropdownButtonFormField<int>(
              initialValue: _maxBodyBytes,
              decoration: const InputDecoration(
                label: LocalizedText('响应正文保留上限'),
              ),
              items:
                  const {
                        256 * 1024: '256 KiB',
                        1024 * 1024: '1 MiB',
                        4 * 1024 * 1024: '4 MiB',
                      }.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
              onChanged: _running
                  ? null
                  : (value) {
                      setState(() => _maxBodyBytes = value ?? 1024 * 1024);
                      _saveDraft();
                    },
            ),
            const SizedBox(height: 8),
            const LocalizedText(
              '为避免泄露凭据，请求头和正文不会写入普通工具草稿。需要保存完整请求时请使用 API 调试台。',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _timeout,
              enabled: !_running,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(label: LocalizedText('超时（秒）')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: const Icon(Icons.send),
          label: const LocalizedText('发送请求'),
        ),
        if (_running) const LinearProgressIndicator(),
        const SizedBox(height: 16),
        if (_output.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _result == null
                  ? SelectableText(
                      _output,
                      style: const TextStyle(fontFamily: 'monospace'),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(
                          _output,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _metricChip(
                              '解析',
                              '${_result!.dnsTime.inMilliseconds} ms',
                            ),
                            _metricChip(
                              '连接',
                              '${_result!.connectTime.inMilliseconds} ms',
                            ),
                            _metricChip(
                              '首字节',
                              '${_result!.timeToFirstByte.inMilliseconds} ms',
                            ),
                            _metricChip(
                              '下载',
                              '${_result!.downloadTime.inMilliseconds} ms',
                            ),
                            _metricChip(
                              '平均速率',
                              '${_formatBytes(_result!.averageBytesPerSecond.round())}/s',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Card(
                          child: ExpansionTile(
                            title: const LocalizedText('连接与响应详情'),
                            subtitle: LocalizedText(
                              '${_result!.contentType ?? '未声明类型'} · '
                              '${_result!.compressionState}',
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              14,
                            ),
                            children: [
                              _detailRow(
                                '本地端点',
                                '${_result!.localAddress ?? '—'}:${_result!.localPort ?? '—'}',
                              ),
                              _detailRow(
                                '远端端点',
                                '${_result!.remoteAddress ?? '—'}:${_result!.remotePort ?? '—'}',
                              ),
                              _detailRow(
                                '等待/握手阶段',
                                '${_result!.preTransferTime.inMilliseconds} ms',
                              ),
                              _detailRow(
                                '连接复用',
                                _result!.persistentConnection ? '支持' : '不支持',
                              ),
                              _detailRow(
                                '内容类型',
                                '${_result!.contentType ?? '未声明'}'
                                    '${_result!.charset == null ? '' : '; charset=${_result!.charset}'}',
                              ),
                            ],
                          ),
                        ),
                        if (_result!.securityObservations.isNotEmpty)
                          Card(
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            child: ExpansionTile(
                              leading: const Icon(Icons.policy_outlined),
                              title: const LocalizedText('响应头安全观察'),
                              subtitle: const LocalizedText(
                                '仅提示头部是否存在，不等同于漏洞结论',
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                14,
                              ),
                              children: [
                                for (final observation
                                    in _result!.securityObservations)
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.info_outline,
                                      size: 18,
                                    ),
                                    title: LocalizedText(
                                      _securityObservationLabel(observation),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (_result!.bodyTruncated) ...[
                          Card(
                            color: Theme.of(
                              context,
                            ).colorScheme.tertiaryContainer,
                            child: ListTile(
                              leading: const Icon(Icons.content_cut_rounded),
                              title: const LocalizedText('响应正文已截断'),
                              subtitle: Text(
                                context.l10n.toolPages.httpBodyTruncatedSummary(
                                  received: _formatBytes(
                                    _result!.receivedBytes,
                                  ),
                                  retained: _formatBytes(_maxBodyBytes),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        SizedBox(
                          height: 420,
                          child: StructuredDataViewer(
                            payload: StructuredPayload(
                              rawText: _result!.body,
                              contentType: _result!.headers['content-type'],
                              source: 'HTTP 诊断',
                              direction: 'RX',
                              metadata: {
                                'statusCode': _result!.statusCode,
                                'remoteAddress': _result!.remoteAddress,
                                'headers': _result!.headers,
                                'dnsMs': _result!.dnsTime.inMilliseconds,
                                'connectMs':
                                    _result!.connectTime.inMilliseconds,
                                'ttfbMs':
                                    _result!.timeToFirstByte.inMilliseconds,
                                'totalMs': _result!.totalTime.inMilliseconds,
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
      ],
    ),
  );
  Future<void> _run() async {
    final timeoutSeconds = int.tryParse(_timeout.text);
    if (timeoutSeconds == null || timeoutSeconds < 1 || timeoutSeconds > 120) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('超时范围为 1～120 秒')));
      return;
    }
    final headers = <String, String>{};
    for (final line in _headers.text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final separator = line.indexOf(':');
      if (separator <= 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText('请求头格式错误：$line')));
        return;
      }
      headers[line.substring(0, separator).trim()] = line
          .substring(separator + 1)
          .trim();
    }
    setState(() {
      _running = true;
      _output = '';
      _result = null;
    });
    try {
      final r = await HttpDiagnosticService().request(
        uri: Uri.parse(_url.text.trim()),
        method: _method,
        headers: headers,
        body: _body.text,
        timeout: Duration(seconds: timeoutSeconds),
        followRedirects: _followRedirects,
        maxRedirects: 5,
        maxBodyBytes: _maxBodyBytes,
      );
      if (!mounted) return;
      final certificate = r.certificate;
      _result = r;
      _output =
          'HTTP ${r.statusCode} ${r.reasonPhrase}\n'
          '${context.tr('远端')} ${r.remoteAddress ?? '—'}\n'
          'DNS ${r.dnsTime.inMilliseconds} ms · TTFB ${r.timeToFirstByte.inMilliseconds} ms · '
          '${context.tr('连接')} ${r.connectTime.inMilliseconds} ms · '
          '${context.tr('下载')} ${r.downloadTime.inMilliseconds} ms · '
          '${context.tr('总计')} ${r.totalTime.inMilliseconds} ms\n'
          '${context.tr('接收')} ${_formatBytes(r.receivedBytes)}'
          '${r.bodyTruncated ? ' (${context.tr('正文已截断')})' : ''}\n'
          '${r.redirects.isEmpty ? '' : '${context.tr('重定向')}：${r.redirects.join(' → ')}\n'}'
          '${certificate == null ? '' : '${context.tr('TLS 证书')}：${certificate.subject}\n${context.tr('签发者')}：${certificate.issuer}\n${context.tr('有效期')}：${certificate.validFrom.toLocal()} → ${certificate.validTo.toLocal()}\n'}'
          '\n${r.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n')}';
      await widget.appState.addHistory(
        tool: 'http',
        title: '$_method ${_url.text}',
        summary: 'HTTP ${r.statusCode} · ${r.totalTime.inMilliseconds} ms',
        detail: _output,
        success: r.statusCode < 500,
      );
    } on Object catch (e) {
      _output = '错误：$e';
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Map<String, Object?> _draftValue() => {
    'url': _url.text,
    'method': _method,
    'timeout': _timeout.text,
    'followRedirects': _followRedirects,
    'maxBodyBytes': _maxBodyBytes,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.http');
    if (!mounted) return;
    if (draft != null) {
      _url.text = draft.payload['url']?.toString() ?? _url.text;
      _method =
          const {
            'GET',
            'HEAD',
            'POST',
            'PUT',
            'PATCH',
            'DELETE',
            'OPTIONS',
          }.contains(draft.payload['method'])
          ? draft.payload['method']!.toString()
          : _method;
      _timeout.text = draft.payload['timeout']?.toString() ?? _timeout.text;
      _followRedirects = draft.payload['followRedirects'] != false;
      _maxBodyBytes =
          (draft.payload['maxBodyBytes'] as num?)?.toInt() ?? _maxBodyBytes;
    }
    final initialUrl = widget.initialUrl?.trim();
    if (initialUrl != null && initialUrl.isNotEmpty) _url.text = initialUrl;
    setState(() {});
    _draftLoaded = true;
  }

  void _saveDraft() {
    if (_draftLoaded) _drafts.scheduleSave('tool.http', _draftValue());
  }

  String _formatBytes(int value) {
    if (value >= 1024 * 1024)
      return '${(value / 1024 / 1024).toStringAsFixed(2)} MiB';
    if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
    return '$value B';
  }

  Widget _metricChip(String label, String value) => Chip(
    avatar: const Icon(Icons.speed_rounded, size: 17),
    label: LocalizedText('$label $value'),
  );

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 112, child: LocalizedText(label)),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );

  String _securityObservationLabel(HttpSecurityObservation observation) =>
      switch (observation) {
        HttpSecurityObservation.plainHttp => 'HTTP 明文传输，内容未加密',
        HttpSecurityObservation.hstsMissing => '未检测到 HSTS 响应头',
        HttpSecurityObservation.contentSecurityPolicyMissing =>
          '未检测到 Content-Security-Policy 响应头',
        HttpSecurityObservation.noSniffMissing =>
          '未检测到 X-Content-Type-Options: nosniff',
        HttpSecurityObservation.referrerPolicyMissing =>
          '未检测到 Referrer-Policy 响应头',
        HttpSecurityObservation.permissionsPolicyMissing =>
          '未检测到 Permissions-Policy 响应头',
      };
}
