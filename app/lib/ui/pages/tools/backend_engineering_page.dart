import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/backend_engineering_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class BackendEngineeringPage extends StatefulWidget {
  const BackendEngineeringPage({super.key, required this.mode, this.appState});

  final String mode;
  final AppState? appState;

  @override
  State<BackendEngineeringPage> createState() => _BackendEngineeringPageState();
}

class _BackendEngineeringPageState extends State<BackendEngineeringPage> {
  final _service = BackendEngineeringService();
  final _input = TextEditingController();
  final _option = TextEditingController();
  final _extra = TextEditingController();
  ToolDraftRepository? _drafts;
  String _result = '';
  String? _error;
  int _sqlAction = 0;

  String get _scope => 'tool.backend.${widget.mode}';

  String get _title => switch (widget.mode) {
    'sql_toolkit' => 'SQL 工具箱',
    'id_inspector' => 'ID 与分布式标识',
    'semver' => 'Semantic Version',
    'http_metadata' => 'HTTP 元数据分析',
    'log_inspector' => '日志分析器',
    _ => '后端工程工具',
  };

  @override
  void initState() {
    super.initState();
    _setExample();
    if (widget.appState != null) {
      _drafts = ToolDraftRepository(widget.appState!.database);
      _restore();
    }
    for (final controller in [_input, _option, _extra]) {
      controller.addListener(_save);
    }
  }

  void _setExample() {
    switch (widget.mode) {
      case 'sql_toolkit':
        _input.text =
            'select id,name,created_at from users where status=:status order by created_at desc;';
        _option.text = 'users';
      case 'id_inspector':
        _input.text = '0192f0bd-5f7a-7b42-8128-93f42028e624';
        _option.text = '1288834974657';
        _extra.text = '10,12';
      case 'semver':
        _input.text = '1.4.0-beta.2';
        _option.text = '1.4.0';
      case 'http_metadata':
        _input.text =
            'HTTP/1.1 200 OK\nContent-Type: application/json; charset=utf-8\nCache-Control: public, max-age=300, stale-while-revalidate=60\nAccess-Control-Allow-Origin: *\nSet-Cookie: sid=example; Path=/; Secure; HttpOnly; SameSite=Lax';
      case 'log_inspector':
        _input.text =
            '{"timestamp":"2026-07-28T12:00:00Z","level":"info","traceId":"01ABCDEF01234567","message":"request completed"}\n2026-07-28T12:00:01Z ERROR trace_id=01ABCDEF01234567 upstream timeout';
    }
  }

  Future<void> _restore() async {
    final draft = await _drafts?.load(_scope);
    if (!mounted || draft == null) return;
    final value = draft.payload;
    setState(() {
      _input.text = value['input']?.toString() ?? _input.text;
      _option.text = value['option']?.toString() ?? _option.text;
      _extra.text = value['extra']?.toString() ?? _extra.text;
      _sqlAction = (value['sqlAction'] as num?)?.toInt() ?? 0;
    });
  }

  void _save() => _drafts?.scheduleSave(_scope, {
    'input': _input.text,
    'option': _option.text,
    'extra': _extra.text,
    'sqlAction': _sqlAction,
  });

  void _run() {
    try {
      final output = switch (widget.mode) {
        'sql_toolkit' => switch (_sqlAction) {
          0 => _service.formatSql(_input.text),
          1 => _service.buildSqlInList(_input.text),
          _ => _service.jsonToInsert(_input.text, _option.text),
        },
        'id_inspector' => _renderIdentifier(),
        'semver' => _renderSemVer(),
        'http_metadata' => _renderHttp(),
        'log_inspector' => _renderLog(),
        _ => '',
      };
      setState(() {
        _result = output;
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _result = '';
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
    _save();
  }

  String _renderIdentifier() {
    final layout = _extra.text
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .toList();
    final result = _service.inspectIdentifier(
      _input.text,
      snowflakeEpoch: int.tryParse(_option.text) ?? 1288834974657,
      nodeBits: layout.isNotEmpty ? layout[0] ?? 10 : 10,
      sequenceBits: layout.length > 1 ? layout[1] ?? 12 : 12,
    );
    return [
      '类型: ${result.kind}',
      '有效: ${result.valid ? '是' : '否'}',
      ...result.fields.entries.map((entry) => '${entry.key}: ${entry.value}'),
      if (result.warning != null) '',
      if (result.warning != null) '注意: ${result.warning}',
    ].join('\n');
  }

  String _renderSemVer() {
    final details = _service.inspectSemVer(_input.text);
    final comparison = _option.text.trim().isEmpty
        ? null
        : _service.compareSemVer(_input.text, _option.text);
    return [
      ...details.entries.map((entry) => '${entry.key}: ${entry.value}'),
      if (comparison != null) '',
      if (comparison != null)
        '与 ${_option.text.trim()} 比较: ${comparison == 0
            ? '相等'
            : comparison > 0
            ? '更高'
            : '更低'}',
    ].join('\n');
  }

  String _renderHttp() {
    final value = _service.inspectHttpHeaders(_input.text);
    return [
      'Headers (${value.headers.length})',
      ...value.headers.entries.map((entry) => '${entry.key}: ${entry.value}'),
      '',
      'Cache-Control',
      if (value.cacheDirectives.isEmpty) '(未设置)',
      ...value.cacheDirectives.entries.map(
        (entry) => '${entry.key} = ${entry.value}',
      ),
      '',
      'Cookies (${value.cookies.length})',
      ...value.cookies.indexed.map(
        (entry) => '#${entry.$1 + 1} ${jsonEncode(entry.$2)}',
      ),
      '',
      '诊断',
      ...value.findings.map((finding) => '• $finding'),
    ].join('\n');
  }

  String _renderLog() {
    final value = _service.inspectLogs(_input.text);
    return [
      '总行数: ${value.total}',
      '首个时间: ${value.firstTimestamp ?? '-'}',
      '最后时间: ${value.lastTimestamp ?? '-'}',
      '',
      '级别分布',
      ...value.levels.entries.map((entry) => '${entry.key}: ${entry.value}'),
      '',
      'Trace / Request ID (${value.traceIds.length})',
      ...value.traceIds,
      '',
      '去除 ANSI 后的日志',
      value.normalized,
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: LocalizedText(_title),
      actions: [
        IconButton(
          tooltip: context.tr('复制结果'),
          onPressed: _result.isEmpty
              ? null
              : () => Clipboard.setData(ClipboardData(text: _result)),
          icon: const Icon(Icons.content_copy_rounded),
        ),
        IconButton(
          tooltip: context.tr('恢复默认'),
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt_rounded),
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 900
          ? Row(
              children: [
                Expanded(child: _inputPanel()),
                const VerticalDivider(width: 1),
                Expanded(child: _resultPanel()),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _inputPanel(),
                const SizedBox(height: 16),
                _resultPanel(),
              ],
            ),
    ),
  );

  Widget _inputPanel() => ListView(
    padding: const EdgeInsets.all(16),
    shrinkWrap: true,
    children: [
      if (widget.mode == 'sql_toolkit') ...[
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              label: LocalizedText('格式化'),
              icon: Icon(Icons.format_align_left_rounded),
            ),
            ButtonSegment(
              value: 1,
              label: Text('IN List'),
              icon: Icon(Icons.list_alt_rounded),
            ),
            ButtonSegment(
              value: 2,
              label: Text('JSON → INSERT'),
              icon: Icon(Icons.table_rows_outlined),
            ),
          ],
          selected: {_sqlAction},
          onSelectionChanged: (value) =>
              setState(() => _sqlAction = value.first),
        ),
        const SizedBox(height: 12),
      ],
      if (widget.mode == 'id_inspector')
        const _HintCard(
          icon: Icons.badge_outlined,
          text: '自动识别 UUID v1/v7、ULID、MongoDB ObjectId 与 Snowflake。',
        ),
      TextField(
        controller: _input,
        minLines: widget.mode == 'id_inspector' || widget.mode == 'semver'
            ? 1
            : 10,
        maxLines: widget.mode == 'id_inspector' || widget.mode == 'semver'
            ? 2
            : 24,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
        decoration: InputDecoration(
          labelText: context.tr(_inputLabel),
          alignLabelWithHint: true,
        ),
      ),
      if (_showOption) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _option,
          decoration: InputDecoration(labelText: context.tr(_optionLabel)),
        ),
      ],
      if (widget.mode == 'id_inspector') ...[
        const SizedBox(height: 12),
        TextField(
          controller: _extra,
          decoration: InputDecoration(
            labelText: context.tr('Snowflake 节点位,序列位'),
          ),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _run,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const LocalizedText('分析'),
      ),
    ],
  );

  String get _inputLabel => switch (widget.mode) {
    'sql_toolkit' =>
      _sqlAction == 1
          ? '每行或逗号分隔的值'
          : _sqlAction == 2
          ? 'JSON Object 或 Object 数组'
          : 'SQL',
    'id_inspector' => '标识符',
    'semver' => '版本 A',
    'http_metadata' => '响应头',
    'log_inspector' => '日志（文本或 JSON Lines）',
    _ => '输入',
  };

  bool get _showOption =>
      (widget.mode == 'sql_toolkit' && _sqlAction == 2) ||
      widget.mode == 'id_inspector' ||
      widget.mode == 'semver';

  String get _optionLabel => switch (widget.mode) {
    'sql_toolkit' => '表名',
    'id_inspector' => 'Snowflake Epoch（毫秒）',
    'semver' => '版本 B（可选比较）',
    _ => '选项',
  };

  Widget _resultPanel() => ListView(
    padding: const EdgeInsets.all(16),
    shrinkWrap: true,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              context.tr('结构化结果'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: context.tr('复制结果'),
            onPressed: _result.isEmpty
                ? null
                : () => Clipboard.setData(ClipboardData(text: _result)),
            icon: const Icon(Icons.copy_all_rounded),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Container(
        constraints: const BoxConstraints(minHeight: 260),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _error == null
              ? Theme.of(context).colorScheme.surfaceContainerLow
              : Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          _error ?? (_result.isEmpty ? context.tr('输入内容后点击分析。') : _result),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13.5,
            height: 1.55,
          ),
        ),
      ),
    ],
  );

  Future<void> _reset() async {
    await _drafts?.reset(_scope);
    _input.clear();
    _option.clear();
    _extra.clear();
    _setExample();
    setState(() {
      _result = '';
      _error = null;
      _sqlAction = 0;
    });
  }

  @override
  void dispose() {
    _drafts?.flush(_scope);
    _drafts?.dispose();
    _input.dispose();
    _option.dispose();
    _extra.dispose();
    super.dispose();
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: LocalizedText(text)),
      ],
    ),
  );
}
