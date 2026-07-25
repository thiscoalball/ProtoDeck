import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/timestamp_workbench_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class TimestampWorkbenchPage extends StatefulWidget {
  const TimestampWorkbenchPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<TimestampWorkbenchPage> createState() => _TimestampWorkbenchPageState();
}

class _TimestampWorkbenchPageState extends State<TimestampWorkbenchPage>
    with WidgetsBindingObserver {
  final _service = TimestampWorkbenchService();
  late final ToolDraftRepository _drafts;
  final _input = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _batch = TextEditingController();
  final _zoneSearch = TextEditingController();
  var _inputZone = 'Asia/Shanghai';
  var _zones = <String>['Etc/UTC', 'Asia/Shanghai'];
  var _tab = 0;
  TimestampInspection? _inspection;
  TimestampCalculation? _calculation;
  List<TimestampInspection> _batchResults = const [];
  String? _error;
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _drafts = ToolDraftRepository(widget.appState.database);
    _input.text = '${DateTime.now().millisecondsSinceEpoch}';
    _start.text = DateTime.now().toUtc().toIso8601String();
    _end.text = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .toIso8601String();
    for (final controller in [_input, _start, _end, _batch]) {
      controller.addListener(_saveDraft);
    }
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    unawaited(_restoreDraft());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_drafts.save('developer.timestamp', _draftPayload()));
    }
  }

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('developer.timestamp');
    if (!mounted || draft == null) return;
    final payload = draft.payload;
    setState(() {
      _input.text = payload['input']?.toString() ?? _input.text;
      _start.text = payload['start']?.toString() ?? _start.text;
      _end.text = payload['end']?.toString() ?? _end.text;
      _batch.text = payload['batch']?.toString() ?? '';
      _inputZone = payload['inputZone']?.toString() ?? _inputZone;
      _tab = (payload['tab'] as num?)?.toInt().clamp(0, 2) ?? 0;
      _zones =
          (payload['zones'] as List?)
              ?.map((value) => value.toString())
              .where(_service.allZones.contains)
              .toList() ??
          _zones;
      if (_zones.isEmpty) _zones = ['Etc/UTC', 'Asia/Shanghai'];
    });
  }

  Map<String, Object?> _draftPayload() => {
    'input': _input.text,
    'start': _start.text,
    'end': _end.text,
    'batch': _batch.text,
    'inputZone': _inputZone,
    'zones': _zones,
    'tab': _tab,
  };

  void _saveDraft() =>
      _drafts.scheduleSave('developer.timestamp', _draftPayload());

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    unawaited(_drafts.save('developer.timestamp', _draftPayload()));
    _drafts.dispose();
    for (final controller in [_input, _start, _end, _batch, _zoneSearch]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('时间工作台'),
      actions: [
        IconButton(
          tooltip: context.tr('使用当前时间'),
          onPressed: () {
            _input.text = '${DateTime.now().millisecondsSinceEpoch}';
            _inspect();
          },
          icon: const Icon(Icons.update_rounded),
        ),
        IconButton(
          tooltip: context.tr('恢复默认'),
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          _liveClock(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: LocalizedText('转换')),
                ButtonSegment(value: 1, label: LocalizedText('时间计算')),
                ButtonSegment(value: 2, label: LocalizedText('批量')),
              ],
              selected: {_tab},
              onSelectionChanged: (value) {
                setState(() => _tab = value.first);
                _saveDraft();
              },
            ),
          ),
          Expanded(
            child: switch (_tab) {
              0 => _convertView(),
              1 => _calculateView(),
              _ => _batchView(),
            },
          ),
        ],
      ),
    ),
  );

  Widget _liveClock() => Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(
          Icons.schedule_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                _now.toIso8601String(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${_now.millisecondsSinceEpoch ~/ 1000} s  ·  ${_now.millisecondsSinceEpoch} ms',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: context.tr('复制毫秒时间戳'),
          onPressed: () => _copy('${_now.millisecondsSinceEpoch}'),
          icon: const Icon(Icons.copy_rounded),
        ),
      ],
    ),
  );

  Widget _convertView() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
    children: [
      TextField(
        controller: _input,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: context.tr('时间戳或日期时间'),
          hintText: '1722096000 / 2026-07-28 12:00:00',
          suffixIcon: IconButton(
            tooltip: context.tr('粘贴'),
            onPressed: () async {
              _input.text =
                  (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
            },
            icon: const Icon(Icons.content_paste_rounded),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _inputZoneField()),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _selectOutputZones,
              icon: const Icon(Icons.public_rounded),
              label: LocalizedText('对比时区（${_zones.length}）'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _inspect,
        icon: const Icon(Icons.sync_alt_rounded),
        label: const LocalizedText('转换并分析'),
      ),
      if (_error != null) _errorCard(),
      if (_inspection case final result?) ...[
        const SizedBox(height: 18),
        _sectionTitle('标准表示', result.inputType),
        if (result.warning case final warning?) _warningCard(warning),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 700
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final value in result.values) _valueCard(value, width),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        _sectionTitle('时区对比', 'IANA · DST'),
        const SizedBox(height: 8),
        ...result.zones.map(_zoneCard),
        const SizedBox(height: 20),
        _sectionTitle('代码片段', 'Backend'),
        const SizedBox(height: 8),
        ...result.codeSamples.entries.map(
          (entry) => _copyRow(entry.key, entry.value),
        ),
      ],
    ],
  );

  Widget _calculateView() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
    children: [
      TextField(
        controller: _start,
        decoration: InputDecoration(labelText: context.tr('开始时间')),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _end,
        decoration: InputDecoration(labelText: context.tr('结束时间')),
      ),
      const SizedBox(height: 10),
      _inputZoneField(),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _calculate,
        icon: const Icon(Icons.calculate_outlined),
        label: const LocalizedText('计算时间差'),
      ),
      if (_error != null) _errorCard(),
      if (_calculation case final value?) ...[
        const SizedBox(height: 18),
        _sectionTitle('计算结果', value.negative ? '负时间差' : '正时间差'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${value.negative ? '−' : ''}${value.days}d ${value.hours}h ${value.minutes}m ${value.seconds}s ${value.milliseconds}ms',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                _copyRow('总秒数', '${value.duration.inMicroseconds / 1000000}'),
                _copyRow('总毫秒数', '${value.duration.inMilliseconds}'),
                _copyRow('总微秒数', '${value.duration.inMicroseconds}'),
              ],
            ),
          ),
        ),
      ],
    ],
  );

  Widget _batchView() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
    children: [
      TextField(
        controller: _batch,
        minLines: 6,
        maxLines: 12,
        decoration: InputDecoration(
          labelText: context.tr('每行一条时间，最多 500 行'),
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 10),
      _inputZoneField(),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _inspectBatch,
        icon: const Icon(Icons.table_rows_outlined),
        label: const LocalizedText('批量转换'),
      ),
      if (_error != null) _errorCard(),
      if (_batchResults.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _sectionTitle('转换结果', '${_batchResults.length} rows'),
            ),
            TextButton.icon(
              onPressed: _copyBatchCsv,
              icon: const Icon(Icons.copy_all_rounded),
              label: const LocalizedText('复制 CSV'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._batchResults.map(
          (value) => Card(
            child: ListTile(
              title: Text(value.source),
              subtitle: Text(
                '${value.values[0].value} s\n${value.instant.toIso8601String()}',
              ),
              isThreeLine: true,
              trailing: IconButton(
                onPressed: () => _copy(value.instant.toIso8601String()),
                icon: const Icon(Icons.copy_rounded),
              ),
            ),
          ),
        ),
      ],
    ],
  );

  Widget _inputZoneField() => DropdownButtonFormField<String>(
    initialValue: _inputZone,
    isExpanded: true,
    decoration: InputDecoration(labelText: context.tr('无时区输入按此时区解释')),
    items: TimestampWorkbenchService.commonZones
        .map((zone) => DropdownMenuItem(value: zone, child: Text(zone)))
        .toList(),
    onChanged: (value) {
      if (value == null) return;
      setState(() => _inputZone = value);
      _saveDraft();
    },
  );

  Widget _sectionTitle(String title, String detail) => Row(
    children: [
      Expanded(
        child: LocalizedText(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      Text(detail, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Widget _valueCard(TimestampValue value, double width) => SizedBox(
    width: width,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(
                    value.label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    value.value,
                    style: TextStyle(
                      fontFamily: value.monospace ? 'monospace' : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.tr('复制'),
              onPressed: () => _copy(value.value),
              icon: const Icon(Icons.copy_rounded, size: 19),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _zoneCard(TimestampZoneValue value) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: const Icon(Icons.language_rounded),
      title: Text(
        value.zone,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${value.localTime}\n${value.offset} · ${value.isDaylightSaving ? context.tr('夏令时') : context.tr('标准时')}',
      ),
      isThreeLine: true,
      trailing: IconButton(
        onPressed: () => _copy(value.localTime),
        icon: const Icon(Icons.copy_rounded),
      ),
    ),
  );

  Widget _copyRow(String label, String value) => Card(
    margin: const EdgeInsets.only(bottom: 7),
    child: ListTile(
      dense: true,
      title: LocalizedText(label),
      subtitle: SelectableText(
        value,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      trailing: IconButton(
        onPressed: () => _copy(value),
        icon: const Icon(Icons.copy_rounded),
      ),
    ),
  );

  Widget _warningCard(String value) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        const SizedBox(width: 9),
        Expanded(child: LocalizedText(value)),
      ],
    ),
  );

  Widget _errorCard() => _warningCard(_error!);

  void _inspect() {
    try {
      final result = _service.inspect(
        _input.text,
        inputZone: _inputZone,
        outputZones: _zones,
      );
      setState(() {
        _inspection = result;
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _inspection = null;
        _error = '$error';
      });
    }
  }

  void _calculate() {
    try {
      final result = _service.difference(
        _start.text,
        _end.text,
        inputZone: _inputZone,
      );
      setState(() {
        _calculation = result;
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _calculation = null;
        _error = '$error';
      });
    }
  }

  void _inspectBatch() {
    try {
      final result = _service.inspectBatch(
        _batch.text,
        inputZone: _inputZone,
        outputZones: _zones,
      );
      setState(() {
        _batchResults = result;
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _batchResults = const [];
        _error = '$error';
      });
    }
  }

  Future<void> _selectOutputZones() async {
    final selected = _zones.toSet();
    _zoneSearch.clear();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          final query = _zoneSearch.text.toLowerCase();
          final zones = _service.allZones
              .where((zone) => zone.toLowerCase().contains(query))
              .take(200)
              .toList();
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * .75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _zoneSearch,
                    onChanged: (_) => update(() {}),
                    decoration: InputDecoration(
                      labelText: context.tr('搜索 IANA 时区'),
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: zones.length,
                    itemBuilder: (context, index) {
                      final zone = zones[index];
                      return CheckboxListTile(
                        value: selected.contains(zone),
                        title: Text(zone),
                        onChanged: (enabled) => update(() {
                          if (enabled == true && selected.length < 12) {
                            selected.add(zone);
                          } else if (enabled != true) {
                            selected.remove(zone);
                          }
                        }),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: LocalizedText('完成（${selected.length}/12）'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted || selected.isEmpty) return;
    setState(() => _zones = selected.toList());
    _saveDraft();
  }

  Future<void> _copyBatchCsv() async {
    final rows = <String>['input,type,unix_seconds,unix_milliseconds,rfc3339'];
    for (final result in _batchResults) {
      String csv(String value) => '"${value.replaceAll('"', '""')}"';
      rows.add(
        [
          csv(result.source),
          csv(result.inputType),
          result.values[0].value,
          result.values[1].value,
          csv(result.instant.toIso8601String()),
        ].join(','),
      );
    }
    await _copy(rows.join('\n'));
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: LocalizedText(context.tr('已复制'))));
  }

  Future<void> _reset() async {
    await _drafts.reset('developer.timestamp');
    if (!mounted) return;
    setState(() {
      _input.text = '${DateTime.now().millisecondsSinceEpoch}';
      _start.text = DateTime.now().toUtc().toIso8601String();
      _end.text = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String();
      _batch.clear();
      _inputZone = 'Asia/Shanghai';
      _zones = ['Etc/UTC', 'Asia/Shanghai'];
      _inspection = null;
      _calculation = null;
      _batchResults = const [];
      _error = null;
    });
  }
}
