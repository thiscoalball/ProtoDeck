import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../data/app_database.dart';
import '../../../state/app_state.dart';

class TransferCenterPage extends StatelessWidget {
  const TransferCenterPage({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('传输中心'),
      actions: [
        IconButton(
          tooltip: context.tr('清理已结束任务'),
          onPressed: appState.database.clearFinishedTransferJobs,
          icon: const Icon(Icons.cleaning_services_outlined),
        ),
      ],
    ),
    body: StreamBuilder<List<TransferJob>>(
      stream: appState.database.watchTransferJobs(),
      builder: (context, snapshot) {
        final jobs = snapshot.data ?? const <TransferJob>[];
        if (jobs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sync_alt, size: 48),
                SizedBox(height: 10),
                LocalizedText('暂无文件传输'),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: jobs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _jobCard(context, jobs[index]),
        );
      },
    ),
  );

  Widget _jobCard(BuildContext context, TransferJob job) {
    final total = job.totalBytes;
    final progress = total == null || total <= 0
        ? null
        : (job.transferredBytes / total).clamp(0.0, 1.0);
    final (icon, color, status) = switch (job.status) {
      'running' => (Icons.sync, Theme.of(context).colorScheme.primary, '传输中'),
      'paused' => (Icons.pause_circle, const Color(0xFFCA7A16), '已暂停'),
      'completed' => (Icons.check_circle, const Color(0xFF168A5B), '已完成'),
      'cancelled' => (Icons.cancel, const Color(0xFF6B7785), '已取消'),
      _ => (Icons.error, Theme.of(context).colorScheme.error, '失败'),
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 9),
                Expanded(
                  child: LocalizedText(
                    job.destinationPath.split(RegExp(r'[/\\]')).last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                LocalizedText(status, style: TextStyle(color: color)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 5),
            LocalizedText(
              '${job.direction == 'upload' ? '上传' : '下载'} · ${job.transferredBytes} / ${total ?? 0} B',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (job.error != null)
              LocalizedText(
                job.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
