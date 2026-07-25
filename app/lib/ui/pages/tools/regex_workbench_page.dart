import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/regex_workbench_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class RegexWorkbenchPage extends StatefulWidget {
  const RegexWorkbenchPage({super.key, required this.appState});
  final AppState appState;

  @override
  State<RegexWorkbenchPage> createState() => _RegexWorkbenchPageState();
}

class _RegexWorkbenchPageState extends State<RegexWorkbenchPage>
    with WidgetsBindingObserver {
  final _service = RegexWorkbenchService();
  final _pattern = TextEditingController();
  final _input = TextEditingController();
  final _replacement = TextEditingController();
  late final ToolDraftRepository _drafts;
  RegexAnalysis? _analysis;
  String? _error;
  var _caseSensitive = true;
  var _multiLine = false;
  var _dotAll = false;
  var _replaceAll = true;
  var _flavor = RegexFlavor.dart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _drafts = ToolDraftRepository(widget.appState.database);
    for (final controller in [_pattern, _input, _replacement]) {
      controller.addListener(_changed);
    }
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final draft = await _drafts.load('developer.regex');
    if (!mounted || draft == null) return;
    final value = draft.payload;
    _pattern.text = value['pattern']?.toString() ?? '';
    _input.text = value['input']?.toString() ?? '';
    _replacement.text = value['replacement']?.toString() ?? '';
    setState(() {
      _caseSensitive = value['caseSensitive'] as bool? ?? true;
      _multiLine = value['multiLine'] as bool? ?? false;
      _dotAll = value['dotAll'] as bool? ?? false;
      _replaceAll = value['replaceAll'] as bool? ?? true;
      _flavor = RegexFlavor.values.firstWhere(
        (item) => item.name == value['flavor'],
        orElse: () => RegexFlavor.dart,
      );
    });
    if (_pattern.text.isNotEmpty) _run();
  }

  Map<String, Object?> _payload() => {
    'pattern': _pattern.text,
    'input': _input.text,
    'replacement': _replacement.text,
    'caseSensitive': _caseSensitive,
    'multiLine': _multiLine,
    'dotAll': _dotAll,
    'replaceAll': _replaceAll,
    'flavor': _flavor.name,
  };

  void _changed() {
    _drafts.scheduleSave('developer.regex', _payload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_drafts.save('developer.regex', _payload()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_drafts.save('developer.regex', _payload()));
    _drafts.dispose();
    _pattern.dispose();
    _input.dispose();
    _replacement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('正则工作台'),
      actions: [
        IconButton(
          tooltip: context.tr('恢复默认'),
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 920
            ? Row(
                children: [
                  SizedBox(width: constraints.maxWidth * .46, child: _editor()),
                  const VerticalDivider(width: 1),
                  Expanded(child: _results()),
                ],
              )
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  _editor(shrink: true),
                  const Divider(height: 1),
                  SizedBox(height: 700, child: _results()),
                ],
              ),
      ),
    ),
  );

  Widget _editor({bool shrink = false}) => ListView(
    shrinkWrap: shrink,
    physics: shrink ? const NeverScrollableScrollPhysics() : null,
    padding: const EdgeInsets.all(16),
    children: [
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<RegexFlavor>(
              initialValue: _flavor,
              decoration: InputDecoration(labelText: context.tr('正则方言')),
              items: RegexFlavor.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(switch (value) {
                        RegexFlavor.dart => 'Dart',
                        RegexFlavor.javascript => 'JavaScript',
                        RegexFlavor.pcre2 => 'PCRE2',
                        RegexFlavor.java => 'Java',
                        RegexFlavor.re2 => 'Go / RE2',
                        RegexFlavor.dotnet => '.NET',
                      }),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _flavor = value);
                _changed();
              },
            ),
          ),
          const SizedBox(width: 10),
          PopupMenuButton<RegexPreset>(
            tooltip: context.tr('常用模板'),
            icon: const Icon(Icons.bookmarks_outlined),
            itemBuilder: (_) => RegexWorkbenchService.presets
                .map(
                  (preset) => PopupMenuItem(
                    value: preset,
                    child: LocalizedText(preset.name),
                  ),
                )
                .toList(),
            onSelected: (preset) {
              _pattern.text = preset.pattern;
              _input.text = preset.sample;
              _run();
            },
          ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _pattern,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: context.tr('正则表达式'),
          prefixText: '/',
          suffixText: '/',
          suffixIcon: IconButton(
            tooltip: context.tr('复制'),
            onPressed: () => _copy(_pattern.text),
            icon: const Icon(Icons.copy_rounded),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          FilterChip(
            label: const Text('i · ignore case'),
            selected: !_caseSensitive,
            onSelected: (value) => setState(() => _caseSensitive = !value),
          ),
          FilterChip(
            label: const Text('m · multiline'),
            selected: _multiLine,
            onSelected: (value) => setState(() => _multiLine = value),
          ),
          FilterChip(
            label: const Text('s · dot all'),
            selected: _dotAll,
            onSelected: (value) => setState(() => _dotAll = value),
          ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _input,
        minLines: 8,
        maxLines: 16,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: context.tr('示例文本'),
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _replacement,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: context.tr(r'替换表达式（可选，支持 $1）'),
          suffixIcon: Tooltip(
            message: context.tr('替换全部'),
            child: Switch(
              value: _replaceAll,
              onChanged: (value) => setState(() => _replaceAll = value),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _run,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const LocalizedText('运行正则'),
      ),
    ],
  );

  Widget _results() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      if (_error != null)
        _notice(_error!, Colors.red, Icons.error_outline_rounded)
      else if (_analysis == null)
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Column(
            children: [
              const Icon(Icons.rule_rounded, size: 46),
              const SizedBox(height: 12),
              LocalizedText(
                '输入表达式与示例文本后运行',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        )
      else
        ..._resultContent(_analysis!),
    ],
  );

  List<Widget> _resultContent(RegexAnalysis value) => [
    Row(
      children: [
        Expanded(
          child: LocalizedText(
            '匹配结果',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Chip(label: LocalizedText('${value.matches.length} 个匹配')),
      ],
    ),
    const SizedBox(height: 8),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SelectableText.rich(
          TextSpan(children: _highlightedSpans(value)),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      ),
    ),
    if (value.warnings.isNotEmpty || value.flavorNotes.isNotEmpty) ...[
      const SizedBox(height: 12),
      ...value.warnings.map(
        (warning) =>
            _notice(warning, Colors.orange, Icons.warning_amber_rounded),
      ),
      ...value.flavorNotes.map(
        (note) => _notice(note, Colors.blue, Icons.info_outline_rounded),
      ),
    ],
    const SizedBox(height: 14),
    ...value.matches.asMap().entries.map(
      (entry) => Card(
        child: ExpansionTile(
          title: Text(
            '#${entry.key + 1} · [${entry.value.start}, ${entry.value.end})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            entry.value.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          trailing: IconButton(
            onPressed: () => _copy(entry.value.text),
            icon: const Icon(Icons.copy_rounded),
          ),
          children: [
            for (final group in entry.value.groups.asMap().entries)
              ListTile(
                dense: true,
                title: Text('Group ${group.key + 1}'),
                subtitle: SelectableText(group.value ?? 'null'),
                trailing: group.value == null
                    ? null
                    : IconButton(
                        onPressed: () => _copy(group.value!),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                      ),
              ),
          ],
        ),
      ),
    ),
    if (_replacement.text.isNotEmpty) ...[
      const SizedBox(height: 18),
      _title('替换预览'),
      const SizedBox(height: 7),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  value.replaced,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                onPressed: () => _copy(value.replaced),
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
        ),
      ),
    ],
    if (value.tokens.isNotEmpty) ...[
      const SizedBox(height: 18),
      _title('语法解释'),
      const SizedBox(height: 7),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: value.tokens
            .map(
              (item) => Tooltip(
                message: item.meaning,
                child: Chip(
                  label: Text(
                    '${item.token} · ${item.meaning}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ],
  ];

  Widget _title(String value) => LocalizedText(
    value,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
  );

  List<InlineSpan> _highlightedSpans(RegexAnalysis analysis) {
    final spans = <InlineSpan>[];
    var cursor = 0;
    final colors = [
      Theme.of(context).colorScheme.primaryContainer,
      Theme.of(context).colorScheme.secondaryContainer,
      Theme.of(context).colorScheme.tertiaryContainer,
    ];
    for (final entry in analysis.matches.asMap().entries) {
      final match = entry.value;
      if (match.start < cursor) continue;
      if (match.start > cursor) {
        spans.add(TextSpan(text: _input.text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: _input.text.substring(match.start, match.end),
          style: TextStyle(
            backgroundColor: colors[entry.key % colors.length],
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < _input.text.length) {
      spans.add(TextSpan(text: _input.text.substring(cursor)));
    }
    return spans;
  }

  Widget _notice(String text, Color color, IconData icon) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 9),
        Expanded(child: LocalizedText(text)),
      ],
    ),
  );

  void _run() {
    try {
      final result = _service.analyze(
        pattern: _pattern.text,
        input: _input.text,
        replacement: _replacement.text,
        caseSensitive: _caseSensitive,
        multiLine: _multiLine,
        dotAll: _dotAll,
        replaceAll: _replaceAll,
        flavor: _flavor,
      );
      setState(() {
        _analysis = result;
        _error = null;
      });
      _changed();
    } on Object catch (error) {
      setState(() {
        _analysis = null;
        _error = '$error';
      });
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: LocalizedText(context.tr('已复制'))));
  }

  Future<void> _reset() async {
    await _drafts.reset('developer.regex');
    if (!mounted) return;
    setState(() {
      _pattern.clear();
      _input.clear();
      _replacement.clear();
      _caseSensitive = true;
      _multiLine = false;
      _dotAll = false;
      _replaceAll = true;
      _flavor = RegexFlavor.dart;
      _analysis = null;
      _error = null;
    });
  }
}
