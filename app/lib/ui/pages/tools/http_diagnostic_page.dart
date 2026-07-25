import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../models/structured_payload.dart';
import '../../../services/http_diagnostic_service.dart';
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
  @override
  void dispose() {
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
                items: const ['GET', 'HEAD', 'POST', 'PUT', 'DELETE']
                    .map(
                      (v) =>
                          DropdownMenuItem(value: v, child: LocalizedText(v)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _method = v!),
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
        if (_method == 'POST' || _method == 'PUT') ...[
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
      );
      final certificate = r.certificate;
      _result = r;
      _output =
          'HTTP ${r.statusCode} ${r.reasonPhrase}\n'
          '远端 ${r.remoteAddress ?? '—'}\n'
          'DNS ${r.dnsTime.inMilliseconds} ms · TTFB ${r.timeToFirstByte.inMilliseconds} ms · '
          '下载 ${r.downloadTime.inMilliseconds} ms · 总计 ${r.totalTime.inMilliseconds} ms\n'
          '${r.redirects.isEmpty ? '' : '重定向：${r.redirects.join(' → ')}\n'}'
          '${certificate == null ? '' : 'TLS 证书：${certificate.subject}\n签发者：${certificate.issuer}\n有效期：${certificate.validFrom.toLocal()} → ${certificate.validTo.toLocal()}\n'}'
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
}
