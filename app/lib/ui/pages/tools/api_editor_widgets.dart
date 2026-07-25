import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../services/api_workbench_service.dart';
import '../../../models/structured_payload.dart';
import '../../widgets/structured_data_viewer.dart';

class ApiFieldRow {
  ApiFieldRow({
    String? id,
    this.enabled = true,
    this.name = '',
    this.value = '',
    this.description = '',
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}_${_nextId++}';

  final String id;
  bool enabled;
  String name;
  String value;
  String description;

  Map<String, Object?> toJson() => {
    'id': id,
    'enabled': enabled,
    'name': name,
    'value': value,
    'description': description,
  };

  factory ApiFieldRow.fromJson(Map<String, Object?> value) => ApiFieldRow(
    id: value['id']?.toString(),
    enabled: value['enabled'] != false,
    name: value['name']?.toString() ?? '',
    value: value['value']?.toString() ?? '',
    description: value['description']?.toString() ?? '',
  );

  static int _nextId = 0;
}

class ApiKeyValueEditor extends StatelessWidget {
  const ApiKeyValueEditor({
    super.key,
    required this.rows,
    required this.onChanged,
    this.nameHint = '参数名',
    this.valueHint = '参数值',
    this.descriptionHint = '说明',
    this.showDescription = false,
    this.suggestions = const [],
  });

  final List<ApiFieldRow> rows;
  final VoidCallback onChanged;
  final String nameHint;
  final String valueHint;
  final String descriptionHint;
  final bool showDescription;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final row in rows)
        Padding(
          key: ValueKey(row.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: row.enabled,
                onChanged: (value) {
                  row.enabled = value ?? true;
                  onChanged();
                },
              ),
              Expanded(
                child: TextFormField(
                  initialValue: row.name,
                  onChanged: (value) {
                    row.name = value;
                    onChanged();
                  },
                  decoration: InputDecoration(
                    hintText: nameHint,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: row.value,
                  onChanged: (value) {
                    row.value = value;
                    onChanged();
                  },
                  decoration: InputDecoration(
                    hintText: valueHint,
                    isDense: true,
                  ),
                ),
              ),
              if (showDescription) ...[
                const SizedBox(width: 7),
                Expanded(
                  child: TextFormField(
                    initialValue: row.description,
                    onChanged: (value) {
                      row.description = value;
                      onChanged();
                    },
                    decoration: InputDecoration(
                      hintText: descriptionHint,
                      isDense: true,
                    ),
                  ),
                ),
              ],
              IconButton(
                onPressed: () {
                  rows.remove(row);
                  onChanged();
                },
                icon: const Icon(Icons.close, size: 19),
                tooltip: context.tr('删除'),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: () {
            rows.add(ApiFieldRow());
            onChanged();
          },
          icon: const Icon(Icons.add, size: 18),
          label: const LocalizedText('添加一行'),
        ),
      ),
    ],
  );
}

Map<String, String> enabledFieldMap(List<ApiFieldRow> rows) => {
  for (final row in rows)
    if (row.enabled && row.name.trim().isNotEmpty) row.name.trim(): row.value,
};

String prettyJsonOrText(String value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
  } on Object {
    return value;
  }
}

class RealtimeMessageCard extends StatelessWidget {
  const RealtimeMessageCard({super.key, required this.message, this.onTap});

  final RealtimeMessage message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (message.direction) {
      'RX' => Colors.green,
      'TX' => Colors.blue,
      'ERR' => Colors.red,
      _ => Colors.grey,
    };
    final preview = message.prettyData.replaceAll('\n', ' ');
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: LocalizedText(
                      message.direction,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  if (message.channel?.isNotEmpty == true)
                    Expanded(
                      child: LocalizedText(
                        message.channel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    )
                  else
                    const Spacer(),
                  LocalizedText('${message.kind} · ${message.size} B'),
                  const SizedBox(width: 8),
                  LocalizedText(
                    DateFormat('HH:mm:ss.SSS').format(message.time),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
              if (message.data.isNotEmpty) ...[
                const SizedBox(height: 8),
                LocalizedText(
                  preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showRealtimeMessageDetails(
  BuildContext context,
  RealtimeMessage message,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .75,
      minChildSize: .4,
      maxChildSize: .95,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        child: Column(
          children: [
            Row(
              children: [
                LocalizedText(
                  '${message.protocol} ${message.direction}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                LocalizedText(
                  DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(message.time),
                ),
              ],
            ),
            if (message.channel != null) ...[
              const SizedBox(height: 8),
              SelectableText('Channel / Topic / Event: ${message.channel}'),
            ],
            if (message.metadata.isNotEmpty) ...[
              const SizedBox(height: 14),
              const LocalizedText(
                '元数据',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(message.metadata),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                const LocalizedText(
                  '内容',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: message.prettyData),
                  ),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            Expanded(
              child: StructuredDataViewer(
                payload: StructuredPayload(
                  rawText: message.data,
                  rawBytes: message.bytes,
                  contentType: message.kind,
                  source: message.protocol,
                  direction: message.direction,
                  metadata: message.metadata,
                  timestamp: message.time,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
