import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../state/app_state.dart';
import '../widgets/page_header.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: '记录',
          subtitle: '最近 100 次本地测试',
          trailing: IconButton(
            tooltip: context.tr('清空记录'),
            onPressed: () => _confirmClear(context),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: state,
            builder: (context, _) {
              if (state.history.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 52),
                      SizedBox(height: 12),
                      LocalizedText('还没有测试记录'),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: state.history.length,
                itemBuilder: (context, index) {
                  final entry = state.history[index];
                  return Card(
                    child: ExpansionTile(
                      leading: Icon(
                        entry.success
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: entry.success
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                      ),
                      title: LocalizedText(
                        entry.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: LocalizedText(
                        '${_format(entry.timestamp)} · ${entry.summary}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: SelectableText(
                            entry.detail.isEmpty ? entry.summary : entry.detail,
                          ),
                        ),
                        OverflowBar(
                          alignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: entry.detail),
                              ),
                              icon: const Icon(Icons.copy),
                              label: const LocalizedText('复制'),
                            ),
                            TextButton.icon(
                              onPressed: () => state.removeHistory(entry.id),
                              icon: const Icon(Icons.delete_outline),
                              label: const LocalizedText('删除'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('清空所有记录？'),
        content: const LocalizedText('该操作只删除本机测试记录，且无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.clearHistory();
  }

  String _format(DateTime time) =>
      '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
