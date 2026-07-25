import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class TransferProgressCard extends StatelessWidget {
  const TransferProgressCard({
    super.key,
    required this.label,
    required this.transferred,
    required this.total,
    required this.paused,
    required this.onPauseResume,
    required this.onCancel,
  });

  final String label;
  final int transferred;
  final int total;
  final bool paused;
  final VoidCallback onPauseResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final value = total <= 0 ? null : (transferred / total).clamp(0.0, 1.0);
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  LinearProgressIndicator(value: value),
                  const SizedBox(height: 3),
                  LocalizedText(
                    '${_size(transferred)} / ${total <= 0 ? '未知' : _size(total)}${paused ? ' · 已暂停' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onPauseResume,
              tooltip: context.tr(paused ? '继续' : '暂停'),
              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            ),
            IconButton(
              onPressed: onCancel,
              tooltip: context.tr('取消传输'),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GiB';
  }
}
