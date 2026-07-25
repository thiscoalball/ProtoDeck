import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/cron_workbench_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class CronWorkbenchPage extends StatefulWidget {
  const CronWorkbenchPage({super.key, required this.appState});
  final AppState appState;

  @override
  State<CronWorkbenchPage> createState() => _CronWorkbenchPageState();
}

class _CronWorkbenchPageState extends State<CronWorkbenchPage> {
  final _service = CronWorkbenchService();
  final _expression = TextEditingController(text: '*/5 * * * *');
  final _count = TextEditingController(text: '12');
  late final ToolDraftRepository _drafts;
  CronInspection? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _restore();
    _expression.addListener(_save);
    _count.addListener(_save);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _restore() async {
    final draft = await _drafts.load('tool.cron_workbench');
    if (!mounted || draft == null) return;
    _expression.text =
        draft.payload['expression']?.toString() ?? _expression.text;
    _count.text = draft.payload['count']?.toString() ?? _count.text;
    _run();
  }

  void _save() => _drafts.scheduleSave('tool.cron_workbench', {
    'expression': _expression.text,
    'count': _count.text,
  });

  void _run() {
    try {
      final value = _service.inspect(
        _expression.text,
        count: (int.tryParse(_count.text) ?? 12).clamp(1, 100),
      );
      setState(() {
        _result = value;
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _result = null;
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
    _save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('Cron 计划工作台')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _expression,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            labelText: context.tr('五段 Crontab 表达式'),
            suffixIcon: IconButton(
              tooltip: context.tr('复制'),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _expression.text)),
              icon: const Icon(Icons.copy_rounded),
            ),
          ),
          onSubmitted: (_) => _run(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: CronWorkbenchService.presets.entries
              .map(
                (entry) => ActionChip(
                  label: LocalizedText(entry.key),
                  onPressed: () {
                    _expression.text = entry.value;
                    _run();
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 150,
              child: TextField(
                controller: _count,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr('未来执行次数')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _run,
                icon: const Icon(Icons.schedule_send_rounded),
                label: const LocalizedText('解析计划'),
              ),
            ),
          ],
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
        if (_result != null) ...[
          const SizedBox(height: 18),
          _overview(_result!),
          const SizedBox(height: 12),
          _nextRuns(_result!),
        ],
      ],
    ),
  );

  Widget _overview(CronInspection value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(value.description),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...value.fields.entries.map(
            (entry) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: LocalizedText(entry.key),
              trailing: LocalizedText(entry.value),
            ),
          ),
          if (value.warnings.isNotEmpty) const Divider(),
          ...value.warnings.map(
            (warning) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline_rounded),
              title: LocalizedText(warning),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _nextRuns(CronInspection value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LocalizedText('未来执行时间'),
          const SizedBox(height: 8),
          for (final entry in value.nextRuns.indexed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 14,
                child: Text(
                  '${entry.$1 + 1}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              title: SelectableText(
                DateFormat('yyyy-MM-dd HH:mm:ss EEE').format(entry.$2),
              ),
              subtitle: Text(entry.$2.timeZoneName),
              trailing: IconButton(
                tooltip: context.tr('复制'),
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: entry.$2.toIso8601String()),
                ),
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
            ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _drafts.flush('tool.cron_workbench');
    _drafts.dispose();
    _expression.dispose();
    _count.dispose();
    super.dispose();
  }
}
