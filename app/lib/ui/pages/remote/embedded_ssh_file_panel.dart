import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:path/path.dart' as path;

import '../../../data/app_database.dart';
import '../../../services/download_destination_service.dart';
import '../../../services/transfer_job_tracker.dart';
import '../../widgets/transfer_progress_card.dart';

enum _ShellSortBy { name, size, time }

class _ShellFileEntry {
  const _ShellFileEntry({
    required this.name,
    required this.directory,
    required this.size,
    required this.modified,
  });

  final String name;
  final bool directory;
  final int size;
  final int modified;
}

/// Remote file fallback for SSH servers without an SFTP subsystem.
/// Directory operations and transfers still run inside encrypted SSH exec
/// channels; no FTP or unencrypted transport is involved.
class EmbeddedSshFilePanel extends StatefulWidget {
  const EmbeddedSshFilePanel({
    super.key,
    required this.client,
    required this.database,
    required this.profileId,
  });

  final SSHClient client;
  final AppDatabase database;
  final String profileId;

  @override
  State<EmbeddedSshFilePanel> createState() => _EmbeddedSshFilePanelState();
}

class _EmbeddedSshFilePanelState extends State<EmbeddedSshFilePanel> {
  final _path = TextEditingController(text: '.');
  List<_ShellFileEntry> _entries = [];
  _ShellSortBy _sort = _ShellSortBy.name;
  bool _ascending = true;
  bool _loading = true;
  String? _error;
  String? _transferLabel;
  int _transferTotal = 0;
  int _transferDone = 0;
  bool _transferPaused = false;
  bool _transferCancelled = false;
  TransferJobTracker? _transferTracker;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 7, 12, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: Color(0xFF39779F),
                    ),
                    SizedBox(width: 5),
                    LocalizedText(
                      'SSH Browser · SCP/Shell 兼容模式',
                      style: TextStyle(fontSize: 11, color: Color(0xFF39779F)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 7),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _parent,
                      icon: const Icon(Icons.arrow_upward),
                      tooltip: context.tr('上级目录'),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _path,
                        onSubmitted: (_) => _load(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          label: LocalizedText('远程目录'),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                      tooltip: context.tr('刷新'),
                    ),
                    PopupMenuButton<String>(
                      tooltip: context.tr('文件操作'),
                      onSelected: _toolbarAction,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'upload',
                          child: LocalizedText('上传文件'),
                        ),
                        PopupMenuItem(
                          value: 'mkdir',
                          child: LocalizedText('新建目录'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _sortHeader(),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_transferLabel != null)
          TransferProgressCard(
            label: _transferLabel!,
            transferred: _transferDone,
            total: _transferTotal,
            paused: _transferPaused,
            onPauseResume: _togglePause,
            onCancel: () => setState(() => _transferCancelled = true),
          ),
        Expanded(
          child: _entries.isEmpty && !_loading
              ? const Center(child: LocalizedText('目录为空'))
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        entry.directory
                            ? Icons.folder_rounded
                            : Icons.insert_drive_file_outlined,
                        color: entry.directory ? const Color(0xFF4A90E2) : null,
                      ),
                      title: LocalizedText(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: entry.directory
                          ? null
                          : LocalizedText(
                              '${entry.size} B · ${_time(entry.modified)}',
                            ),
                      onTap: entry.directory
                          ? () {
                              _path.text = _join(_path.text, entry.name);
                              _load();
                            }
                          : null,
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) => _entryAction(action, entry),
                        itemBuilder: (_) => [
                          if (!entry.directory)
                            const PopupMenuItem(
                              value: 'download',
                              child: LocalizedText('下载'),
                            ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: LocalizedText('重命名'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: LocalizedText('删除'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Widget _sortHeader() => SizedBox(
    height: 38,
    child: Row(
      children: [
        Expanded(child: _sortButton('名称', _ShellSortBy.name)),
        SizedBox(width: 68, child: _sortButton('大小', _ShellSortBy.size)),
        SizedBox(width: 88, child: _sortButton('时间', _ShellSortBy.time)),
      ],
    ),
  );

  Widget _sortButton(String label, _ShellSortBy value) => TextButton(
    onPressed: () => setState(() {
      if (_sort == value) {
        _ascending = !_ascending;
      } else {
        _sort = value;
        _ascending = true;
      }
      _sortEntries();
    }),
    child: LocalizedText(
      '$label${_sort == value ? (_ascending ? ' ▲' : ' ▼') : ''}',
      style: const TextStyle(fontSize: 12),
    ),
  );

  Future<void> _load({bool initial = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (initial || _path.text.trim().isEmpty || _path.text.trim() == '.') {
        final home = utf8.decode(await widget.client.run('pwd')).trim();
        if (home.isNotEmpty) _path.text = home.split('\n').last.trim();
      }
      final quoted = _quote(_path.text.trim());
      final command =
          '''
for f in $quoted/* $quoted/.[!.]* $quoted/..?*; do
  [ -e "\$f" ] || [ -L "\$f" ] || continue
  if [ -d "\$f" ]; then t=d; else t=f; fi
  s=0; m=0
  v=\$(stat -c %s "\$f" 2>/dev/null) && s=\$v
  v=\$(stat -c %Y "\$f" 2>/dev/null) && m=\$v
  n=\${f##*/}
  printf '%s\\t%s\\t%s\\t%s\\n' "\$t" "\$s" "\$m" "\$n"
done
''';
      final output = utf8.decode(await widget.client.run(command));
      final entries = <_ShellFileEntry>[];
      for (final line in const LineSplitter().convert(output)) {
        final fields = line.split('\t');
        if (fields.length < 4) continue;
        entries.add(
          _ShellFileEntry(
            name: fields.sublist(3).join('\t'),
            directory: fields[0] == 'd',
            size: int.tryParse(fields[1]) ?? 0,
            modified: int.tryParse(fields[2]) ?? 0,
          ),
        );
      }
      _entries = entries;
      _sortEntries();
    } on Object catch (error) {
      _error = '读取失败：$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sortEntries() {
    _entries.sort((a, b) {
      if (a.directory != b.directory) return a.directory ? -1 : 1;
      var result = switch (_sort) {
        _ShellSortBy.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        _ShellSortBy.size => a.size.compareTo(b.size),
        _ShellSortBy.time => a.modified.compareTo(b.modified),
      };
      if (result == 0) {
        result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _ascending ? result : -result;
    });
  }

  void _parent() {
    final current = _path.text.replaceAll(RegExp(r'/+$'), '');
    final slash = current.lastIndexOf('/');
    _path.text = slash <= 0 ? '/' : current.substring(0, slash);
    _load();
  }

  Future<void> _toolbarAction(String action) async {
    if (action == 'mkdir') {
      final name = await _ask('新建目录', '目录名称');
      if (name != null) {
        await _runCommand('mkdir ${_quote(_join(_path.text, name))}');
      }
    } else {
      final result = await FilePicker.platform.pickFiles();
      final local = result?.files.single.path;
      if (local == null) return;
      await _run(() async {
        final remotePath = _join(_path.text, path.basename(local));
        final source = File(local);
        await _beginTransfer(
          '上传 ${path.basename(local)}',
          await source.length(),
          direction: 'upload',
          source: local,
          destination: remotePath,
        );
        final session = await widget.client.execute(
          'cat > ${_quote(remotePath)}',
        );
        try {
          await session.stdin.addStream(_trackedRead(source));
          await session.stdin.close();
          await session.done;
          if (_transferCancelled) {
            await widget.client.run('rm -f ${_quote(remotePath)}');
            await _transferTracker?.cancel(_transferDone);
            throw StateError('上传已取消，远程临时文件已删除');
          }
          if (session.exitCode != 0) {
            throw StateError('上传失败，退出码 ${session.exitCode}');
          }
          await _transferTracker?.complete(_transferDone);
        } finally {
          _endTransfer();
        }
      });
    }
    await _load();
  }

  Future<void> _entryAction(String action, _ShellFileEntry entry) async {
    final remotePath = _join(_path.text, entry.name);
    if (action == 'download') {
      final saveDialogTitle = context.tr('保存下载文件');
      final staging = await DownloadDestinationService.createStagingFile(
        fileName: entry.name,
      );
      UserSavedFile? saved;
      await _run(() async {
        try {
          await _beginTransfer(
            '下载 ${entry.name}',
            entry.size,
            direction: 'download',
            source: remotePath,
            destination: entry.name,
          );
          final session = await widget.client.execute(
            'cat ${_quote(remotePath)}',
          );
          final sink = staging.openWrite();
          try {
            await for (final chunk in session.stdout) {
              await _waitTransfer();
              if (_transferCancelled) break;
              sink.add(chunk);
              _advanceTransfer(chunk.length);
            }
            await sink.close();
            if (_transferCancelled) {
              session.close();
              await _transferTracker?.cancel(_transferDone);
              throw StateError('下载已取消，未完成文件已删除');
            }
            await session.done;
            if (session.exitCode != 0) {
              throw StateError('下载失败，退出码 ${session.exitCode}');
            }
            await _transferTracker?.complete(_transferDone);
          } finally {
            await sink.close();
            _endTransfer();
          }
          saved = await DownloadDestinationService.saveStagedFile(
            stagingFile: staging,
            fileName: entry.name,
            dialogTitle: saveDialogTitle,
          );
        } finally {
          await DownloadDestinationService.discardStagingFile(staging);
        }
      });
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedText('已保存：${saved!.displayLocation}')),
        );
      }
    } else if (action == 'rename') {
      final name = await _ask('重命名', '新名称', initial: entry.name);
      if (name != null) {
        await _runCommand(
          'mv ${_quote(remotePath)} ${_quote(_join(_path.text, name))}',
        );
      }
    } else {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: LocalizedText('删除 ${entry.name}？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const LocalizedText('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const LocalizedText('删除'),
                ),
              ],
            ),
          ) ??
          false;
      if (confirmed) {
        await _runCommand(
          entry.directory
              ? 'rmdir ${_quote(remotePath)}'
              : 'rm -f ${_quote(remotePath)}',
        );
      }
    }
    await _load();
  }

  Future<void> _runCommand(String command) => _run(() async {
    final session = await widget.client.execute(command);
    final stderr = await utf8.decoder.bind(session.stderr).join();
    await session.done;
    if (session.exitCode != 0) {
      throw StateError(
        stderr.trim().isEmpty ? '退出码 ${session.exitCode}' : stderr.trim(),
      );
    }
  });

  Future<void> _run(Future<void> Function() action) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await action();
    } on Object catch (error) {
      await _transferTracker?.fail(_transferDone, error);
      _error = '操作失败：$error';
    } finally {
      _transferTracker = null;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _beginTransfer(
    String label,
    int total, {
    required String direction,
    required String source,
    required String destination,
  }) async {
    final tracker = TransferJobTracker(
      database: widget.database,
      profileId: widget.profileId,
      direction: direction,
      sourcePath: source,
      destinationPath: destination,
      totalBytes: total,
    );
    await tracker.start();
    _transferTracker = tracker;
    if (!mounted) return;
    setState(() {
      _transferLabel = label;
      _transferTotal = total;
      _transferDone = 0;
      _transferPaused = false;
      _transferCancelled = false;
    });
  }

  void _advanceTransfer(int bytes) {
    if (mounted) setState(() => _transferDone += bytes);
    final tracker = _transferTracker;
    if (tracker != null) unawaited(tracker.progress(_transferDone));
  }

  void _togglePause() {
    setState(() => _transferPaused = !_transferPaused);
    final tracker = _transferTracker;
    if (tracker == null) return;
    unawaited(
      _transferPaused
          ? tracker.pause(_transferDone)
          : tracker.resume(_transferDone),
    );
  }

  Future<void> _waitTransfer() async {
    while (_transferPaused && !_transferCancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  Stream<Uint8List> _trackedRead(File file) async* {
    await for (final chunk in file.openRead()) {
      await _waitTransfer();
      if (_transferCancelled) break;
      _advanceTransfer(chunk.length);
      yield Uint8List.fromList(chunk);
    }
  }

  void _endTransfer() {
    if (!mounted) return;
    setState(() {
      _transferLabel = null;
      _transferPaused = false;
    });
  }

  Future<String?> _ask(
    String title,
    String label, {
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: LocalizedText(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const LocalizedText('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result == null || result.isEmpty || result.contains('/')
        ? null
        : result;
  }

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
  String _join(String base, String name) =>
      '${base.replaceAll(RegExp(r'/+$'), '')}/$name';
  String _time(int seconds) => seconds <= 0
      ? '—'
      : DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
        ).toLocal().toString().substring(0, 16);
}
