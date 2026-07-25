import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/developer_tools_service.dart';
import '../../../services/structured_data_workbench_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class StructuredDataWorkbenchPage extends StatefulWidget {
  const StructuredDataWorkbenchPage({
    super.key,
    this.appState,
    this.initialMode = 'format',
  });

  final AppState? appState;
  final String initialMode;

  @override
  State<StructuredDataWorkbenchPage> createState() =>
      _StructuredDataWorkbenchPageState();
}

class _StructuredDataWorkbenchPageState
    extends State<StructuredDataWorkbenchPage> {
  final _service = StructuredDataWorkbenchService();
  final _developer = DeveloperToolsService();
  final _source = TextEditingController(
    text: '{\n  "service": "ProtoDeck",\n  "version": 1,\n  "enabled": true\n}',
  );
  final _secondary = TextEditingController();
  final _argument = TextEditingController(text: r'$.service');
  ToolDraftRepository? _drafts;
  late String _mode;
  String _result = '';
  String? _error;
  String? _draftWarning;
  bool _sortKeys = false;
  bool _compact = false;

  static const _modes = <String, String>{
    'format': '格式化',
    'query': 'JSONPath',
    'convert': '格式转换',
    'diff': '语义对比',
    'schema': 'Schema',
    'model': '代码模型',
  };

  static const _sections = <String, _WorkbenchSection>{
    'process': _WorkbenchSection(
      label: '处理',
      icon: Icons.data_object_rounded,
      modes: ['format', 'query', 'convert'],
    ),
    'validate': _WorkbenchSection(
      label: '校验',
      icon: Icons.fact_check_outlined,
      modes: ['diff', 'schema'],
    ),
    'generate': _WorkbenchSection(
      label: '生成',
      icon: Icons.code_rounded,
      modes: ['model'],
    ),
  };

  static const _convertDirections = <String>{
    'json_yaml',
    'yaml_json',
    'csv_json',
    'json_csv',
  };

  static const _modelLanguages = <String>{
    'TypeScript',
    'Go',
    'Kotlin',
    'Java',
    'Dart',
  };

  @override
  void initState() {
    super.initState();
    _mode = _modes.containsKey(widget.initialMode)
        ? widget.initialMode
        : 'format';
    if (widget.appState != null) {
      _drafts = ToolDraftRepository(widget.appState!.database);
      _restore();
    }
    for (final controller in [_source, _secondary, _argument]) {
      controller.addListener(_save);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _restore() async {
    try {
      final draft = await _drafts?.load('tool.structured_data');
      if (!mounted || draft == null) return;
      final value = draft.payload;
      final restoredMode = value['mode']?.toString();
      final safeMode = _modes.containsKey(restoredMode) ? restoredMode! : _mode;
      final restoredArgument = value['argument']?.toString() ?? '';
      setState(() {
        _mode = safeMode;
        _source.text = value['source']?.toString() ?? _source.text;
        _secondary.text = value['secondary']?.toString() ?? '';
        _argument.text = _safeArgument(safeMode, restoredArgument);
        _sortKeys = value['sortKeys'] == true;
        _compact = value['compact'] == true;
        _draftWarning = null;
      });
      _run();
    } on Object {
      if (!mounted) return;
      setState(() {
        _draftWarning = '无法恢复上次草稿，已使用默认数据。';
      });
    }
  }

  String _safeArgument(String mode, String value) => switch (mode) {
    'query' => value.trim().isEmpty ? r'$.service' : value,
    'convert' => _convertDirections.contains(value) ? value : 'json_yaml',
    'model' => _modelLanguages.contains(value) ? value : 'TypeScript',
    _ => value,
  };

  String get _sectionId => _sections.entries
      .firstWhere((entry) => entry.value.modes.contains(_mode))
      .key;

  void _selectSection(String sectionId) {
    final section = _sections[sectionId];
    if (section == null || section.modes.contains(_mode)) return;
    _selectMode(section.modes.first);
  }

  void _selectMode(String mode) {
    if (!_modes.containsKey(mode)) return;
    setState(() {
      _mode = mode;
      _argument.text = switch (mode) {
        'query' => r'$.service',
        'convert' => 'json_yaml',
        'model' => 'TypeScript',
        _ => _argument.text,
      };
    });
    _run();
  }

  void _save() => _drafts?.scheduleSave('tool.structured_data', {
    'mode': _mode,
    'source': _source.text,
    'secondary': _secondary.text,
    'argument': _argument.text,
    'sortKeys': _sortKeys,
    'compact': _compact,
  });

  void _run() {
    try {
      final output = switch (_mode) {
        'format' => _service.formatJson(
          _source.text,
          sortKeys: _sortKeys,
          compact: _compact,
        ),
        'query' => _developer.queryJson(_source.text, _argument.text),
        'convert' => _developer.convertStructuredData(
          _source.text,
          _argument.text.isEmpty ? 'json_yaml' : _argument.text,
        ),
        'diff' =>
          _service
              .compare(_source.text, _secondary.text)
              .map(
                (change) =>
                    '${change.kind.toUpperCase().padRight(7)} ${change.path}\n'
                    '  - ${_preview(change.before)}\n  + ${_preview(change.after)}',
              )
              .join('\n'),
        'schema' =>
          _secondary.text.trim().isEmpty
              ? _service.inferSchema(_source.text)
              : _service
                    .validateSchema(_source.text, _secondary.text)
                    .map((issue) => '${issue.path}: ${issue.message}')
                    .join('\n'),
        'model' => _service.generateModel(
          _source.text,
          _argument.text.isEmpty ? 'TypeScript' : _argument.text,
        ),
        _ => '',
      };
      setState(() {
        _result = output.isEmpty && _mode == 'diff' ? '数据语义一致，没有差异。' : output;
        if (_mode == 'schema' &&
            _secondary.text.trim().isNotEmpty &&
            output.isEmpty) {
          _result = '验证通过，没有发现 Schema 约束问题。';
        }
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
        _result = '';
      });
    }
    _save();
  }

  String _preview(Object? value) {
    if (value == null) return 'null';
    final encoded = value is String ? value : jsonEncode(value);
    return encoded.length > 240 ? '${encoded.substring(0, 240)}…' : encoded;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('JSON 与数据工作台'),
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
    body: Column(
      children: [
        if (_draftWarning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(context.tr(_draftWarning!)),
                trailing: IconButton(
                  tooltip: context.tr('关闭'),
                  onPressed: () => setState(() => _draftWarning = null),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              key: const Key('structured-data-sections'),
              segments: [
                for (final entry in _sections.entries)
                  ButtonSegment<String>(
                    value: entry.key,
                    icon: Icon(entry.value.icon, size: 18),
                    label: LocalizedText(entry.value.label),
                  ),
              ],
              selected: {_sectionId},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  _selectSection(selection.first),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return constraints.maxWidth >= 900
                  ? Row(
                      children: [
                        Expanded(child: _editor(scrollable: true)),
                        const VerticalDivider(width: 1),
                        Expanded(child: _output(scrollable: true)),
                      ],
                    )
                  : ListView(
                      key: const Key('structured-data-mobile-scroll'),
                      padding: const EdgeInsets.all(16),
                      children: [
                        _editor(scrollable: false),
                        const SizedBox(height: 16),
                        _output(scrollable: false),
                      ],
                    );
            },
          ),
        ),
      ],
    ),
  );

  Widget _editor({required bool scrollable}) {
    final children = <Widget>[
      _modePicker(),
      const SizedBox(height: 14),
      TextField(
        controller: _source,
        minLines: 12,
        maxLines: 24,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
        decoration: InputDecoration(
          labelText: context.tr('输入数据'),
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 12),
      if (_mode == 'diff' || _mode == 'schema')
        TextField(
          controller: _secondary,
          minLines: 6,
          maxLines: 14,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
          decoration: InputDecoration(
            labelText: context.tr(
              _mode == 'diff' ? '对比数据' : 'JSON Schema（留空则自动推断）',
            ),
            alignLabelWithHint: true,
          ),
        ),
      if ({'query', 'convert', 'model'}.contains(_mode)) ...[
        const SizedBox(height: 12),
        if (_mode == 'query')
          TextField(
            controller: _argument,
            decoration: const InputDecoration(labelText: 'JSONPath'),
          )
        else
          DropdownButtonFormField<String>(
            key: ValueKey('structured-data-argument-$_mode'),
            initialValue: _argument.text,
            decoration: InputDecoration(
              labelText: context.tr(_mode == 'convert' ? '转换方向' : '目标语言'),
            ),
            items:
                (_mode == 'convert'
                        ? const {
                            'json_yaml': 'JSON → YAML',
                            'yaml_json': 'YAML → JSON',
                            'csv_json': 'CSV → JSON',
                            'json_csv': 'JSON → CSV',
                          }
                        : const {
                            'TypeScript': 'TypeScript',
                            'Go': 'Go',
                            'Kotlin': 'Kotlin',
                            'Java': 'Java',
                            'Dart': 'Dart',
                          })
                    .entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
            onChanged: (value) {
              if (value == null) return;
              _argument.text = value;
              _run();
            },
          ),
      ],
      if (_mode == 'format') ...[
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const LocalizedText('递归排序 Key'),
              selected: _sortKeys,
              onSelected: (value) {
                setState(() => _sortKeys = value);
                _run();
              },
            ),
            FilterChip(
              label: const LocalizedText('压缩输出'),
              selected: _compact,
              onSelected: (value) {
                setState(() => _compact = value);
                _run();
              },
            ),
          ],
        ),
      ],
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _run,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const LocalizedText('执行'),
      ),
    ];
    if (scrollable) {
      return ListView(padding: const EdgeInsets.all(16), children: children);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _modePicker() {
    final section = _sections[_sectionId]!;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('选择功能'),
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (constraints.maxWidth < 560)
            DropdownButtonFormField<String>(
              key: ValueKey('structured-data-mode-select-$_sectionId'),
              initialValue: _mode,
              isExpanded: true,
              decoration: InputDecoration(
                prefixIcon: Icon(_modeIcon(_mode), size: 20),
                labelText: context.tr('当前操作'),
              ),
              items: [
                for (final mode in section.modes)
                  DropdownMenuItem<String>(
                    value: mode,
                    child: LocalizedText(_modes[mode]!),
                  ),
              ],
              onChanged: (mode) {
                if (mode != null) _selectMode(mode);
              },
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in section.modes)
                  ChoiceChip(
                    key: Key('structured-data-mode-$mode'),
                    label: LocalizedText(_modes[mode]!),
                    selected: _mode == mode,
                    showCheckmark: false,
                    avatar: Icon(_modeIcon(mode), size: 17),
                    onSelected: (_) => _selectMode(mode),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  IconData _modeIcon(String mode) => switch (mode) {
    'format' => Icons.format_align_left_rounded,
    'query' => Icons.manage_search_rounded,
    'convert' => Icons.swap_horiz_rounded,
    'diff' => Icons.difference_outlined,
    'schema' => Icons.rule_folder_outlined,
    'model' => Icons.code_rounded,
    _ => Icons.data_object_rounded,
  };

  Widget _output({required bool scrollable}) {
    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              context.tr('结果'),
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
      if (_error != null)
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(context.tr(_error!)),
          ),
        )
      else
        Container(
          constraints: const BoxConstraints(minHeight: 260),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(
            context.tr(_result),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ),
    ];
    if (scrollable) {
      return ListView(padding: const EdgeInsets.all(16), children: children);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Future<void> _reset() async {
    await _drafts?.reset('tool.structured_data');
    _source.text =
        '{\n  "service": "ProtoDeck",\n  "version": 1,\n  "enabled": true\n}';
    _secondary.clear();
    _argument.text = r'$.service';
    setState(() {
      _mode = 'format';
      _sortKeys = false;
      _compact = false;
    });
    _run();
  }

  @override
  void dispose() {
    _drafts?.flush('tool.structured_data');
    _drafts?.dispose();
    _source.dispose();
    _secondary.dispose();
    _argument.dispose();
    super.dispose();
  }
}

class _WorkbenchSection {
  const _WorkbenchSection({
    required this.label,
    required this.icon,
    required this.modes,
  });

  final String label;
  final IconData icon;
  final List<String> modes;
}
