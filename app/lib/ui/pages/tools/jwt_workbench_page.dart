import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/jwt_workbench_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class JwtWorkbenchPage extends StatefulWidget {
  const JwtWorkbenchPage({super.key, required this.appState});
  final AppState appState;

  @override
  State<JwtWorkbenchPage> createState() => _JwtWorkbenchPageState();
}

class _JwtWorkbenchPageState extends State<JwtWorkbenchPage> {
  final _service = JwtWorkbenchService();
  final _token = TextEditingController();
  final _secret = TextEditingController();
  final _header = TextEditingController(
    text: '{\n  "alg": "HS256",\n  "typ": "JWT"\n}',
  );
  final _payload = TextEditingController(
    text:
        '{\n  "sub": "user-123",\n  "iat": 1785211200,\n  "exp": 1785214800\n}',
  );
  late final ToolDraftRepository _drafts;
  int _tab = 0;
  String _algorithm = 'HS256';
  JwtInspection? _inspection;
  String _result = '';
  String? _error;
  bool _showSecret = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _restore();
    for (final controller in [_token, _header, _payload]) {
      controller.addListener(_save);
    }
  }

  Future<void> _restore() async {
    final draft = await _drafts.load('tool.jwt_workbench');
    if (!mounted || draft == null) return;
    final value = draft.payload;
    setState(() {
      _token.text = value['token']?.toString() ?? '';
      _header.text = value['header']?.toString() ?? _header.text;
      _payload.text = value['payload']?.toString() ?? _payload.text;
      _algorithm = value['algorithm']?.toString() ?? _algorithm;
      _tab = (value['tab'] as num?)?.toInt() ?? 0;
    });
  }

  void _save() => _drafts.scheduleSave('tool.jwt_workbench', {
    'token': _token.text,
    'header': _header.text,
    'payload': _payload.text,
    'algorithm': _algorithm,
    'tab': _tab,
  });

  void _run() {
    try {
      if (_tab == 0) {
        final value = _service.inspect(_token.text, secret: _secret.text);
        setState(() {
          _inspection = value;
          _result = [
            'Header',
            const JsonEncoder.withIndent('  ').convert(value.header),
            '',
            'Payload',
            const JsonEncoder.withIndent('  ').convert(value.payload),
            '',
            'Algorithm: ${value.algorithm}',
            'Signature: ${value.signatureStatus}',
          ].join('\n');
          _error = null;
        });
      } else {
        final token = _service.sign(
          headerSource: _header.text,
          payloadSource: _payload.text,
          algorithm: _algorithm,
          secret: _secret.text,
        );
        setState(() {
          _result = token;
          _inspection = _service.inspect(token, secret: _secret.text);
          _error = null;
        });
      }
    } on Object catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
        _result = '';
        _inspection = null;
      });
    }
    _save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('JWT 工作台')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              label: LocalizedText('解析与验签'),
              icon: Icon(Icons.fact_check_outlined),
            ),
            ButtonSegment(
              value: 1,
              label: LocalizedText('HMAC 签发'),
              icon: Icon(Icons.draw_outlined),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (value) => setState(() {
            _tab = value.first;
            _result = '';
            _inspection = null;
          }),
        ),
        const SizedBox(height: 14),
        if (_tab == 0)
          TextField(
            controller: _token,
            minLines: 4,
            maxLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'JWT',
              alignLabelWithHint: true,
            ),
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final editors = [
                _jsonEditor(_header, 'Header JSON'),
                _jsonEditor(_payload, 'Payload JSON'),
              ];
              return constraints.maxWidth >= 760
                  ? Row(
                      children: [
                        Expanded(child: editors[0]),
                        const SizedBox(width: 12),
                        Expanded(child: editors[1]),
                      ],
                    )
                  : Column(
                      children: [
                        editors[0],
                        const SizedBox(height: 12),
                        editors[1],
                      ],
                    );
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _algorithm,
            decoration: const InputDecoration(labelText: 'Algorithm'),
            items: const ['HS256', 'HS384', 'HS512']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => _algorithm = value ?? _algorithm),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _secret,
          obscureText: !_showSecret,
          decoration: InputDecoration(
            labelText: context.tr(
              _tab == 0 ? 'HMAC 验签密钥（可选）' : 'HMAC 签发密钥（不会保存）',
            ),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _showSecret = !_showSecret),
              icon: Icon(
                _showSecret
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const LocalizedText('密钥只保存在当前页面内存中，不会写入草稿或日志。'),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _run,
          icon: const Icon(Icons.play_arrow_rounded),
          label: LocalizedText(_tab == 0 ? '解析 Token' : '签发 Token'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(context.tr(_error!)),
            ),
          ),
        ],
        if (_inspection != null) ...[
          const SizedBox(height: 18),
          _summary(_inspection!),
        ],
        if (_result.isNotEmpty) ...[const SizedBox(height: 14), _resultCard()],
      ],
    ),
  );

  Widget _jsonEditor(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        minLines: 7,
        maxLines: 12,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      );

  Widget _summary(JwtInspection value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(
                  value.algorithm.isEmpty ? 'alg missing' : value.algorithm,
                ),
              ),
              Chip(
                avatar: Icon(
                  value.signatureStatus == 'VALID'
                      ? Icons.verified_rounded
                      : Icons.info_outline_rounded,
                  size: 18,
                ),
                label: Text(value.signatureStatus),
              ),
            ],
          ),
          if (value.claims.isNotEmpty) ...[
            const SizedBox(height: 12),
            const LocalizedText('标准声明'),
            ...value.claims.entries.map(
              (entry) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(entry.key),
                subtitle: SelectableText(entry.value),
                trailing: IconButton(
                  tooltip: context.tr('复制'),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: entry.value)),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
              ),
            ),
          ],
          if (value.warnings.isNotEmpty) ...[
            const Divider(),
            ...value.warnings.map(
              (warning) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: LocalizedText(warning),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _resultCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: LocalizedText(_tab == 0 ? '解码内容' : '已签发 Token')),
              IconButton(
                tooltip: context.tr('复制结果'),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _result)),
                icon: const Icon(Icons.copy_all_rounded),
              ),
            ],
          ),
          SelectableText(
            _result,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _drafts.flush('tool.jwt_workbench');
    _drafts.dispose();
    _token.dispose();
    _secret.dispose();
    _header.dispose();
    _payload.dispose();
    super.dispose();
  }
}
