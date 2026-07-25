import 'dart:async';
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

enum _SortBy { name, size, time }

class EmbeddedSftpPanel extends StatefulWidget {
  const EmbeddedSftpPanel({
    super.key,
    required this.sftp,
    required this.database,
    required this.profileId,
  });
  final SftpClient sftp;
  final AppDatabase database;
  final String profileId;

  @override
  State<EmbeddedSftpPanel> createState() => _EmbeddedSftpPanelState();
}

class _EmbeddedSftpPanelState extends State<EmbeddedSftpPanel> {
  final _path = TextEditingController(text: '.');
  List<SftpName> _entries = [];
  _SortBy _sort = _SortBy.name;
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
    _load();
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 7),
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
                      child: ListTile(
                        leading: Icon(Icons.upload_file),
                        title: LocalizedText('上传文件'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'mkdir',
                      child: ListTile(
                        leading: Icon(Icons.create_new_folder_outlined),
                        title: LocalizedText('新建目录'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _sortHeader(),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: LocalizedText(
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
                    final directory = entry.attr.isDirectory;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        directory
                            ? Icons.folder_rounded
                            : Icons.insert_drive_file_outlined,
                        color: directory ? const Color(0xFF4A90E2) : null,
                      ),
                      title: LocalizedText(
                        entry.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: directory
                          ? null
                          : LocalizedText(
                              '${entry.attr.size ?? 0} B · ${_time(entry.attr.modifyTime)}',
                              maxLines: 1,
                            ),
                      onTap: directory
                          ? () {
                              _path.text = _join(_path.text, entry.filename);
                              _load();
                            }
                          : null,
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) => _entryAction(action, entry),
                        itemBuilder: (_) => [
                          if (!directory)
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
        Expanded(child: _sortButton('名称', _SortBy.name)),
        SizedBox(width: 68, child: _sortButton('大小', _SortBy.size)),
        SizedBox(width: 88, child: _sortButton('时间', _SortBy.time)),
      ],
    ),
  );

  Widget _sortButton(String label, _SortBy value) => TextButton(
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requested = _path.text.trim().isEmpty ? '.' : _path.text.trim();
      var resolved = requested;
      try {
        // SSH_FXP_REALPATH is the standard way to discover the authenticated
        // user's initial directory and works for POSIX and non-POSIX servers.
        resolved = await widget.sftp.absolute(requested);
      } on Object {
        // A few otherwise usable SFTP v3 servers implement OPENDIR/READDIR
        // but reject REALPATH. Keep the protocol-based browser functional.
      }
      final entries = await widget.sftp.listdir(resolved);
      _path.text = resolved;
      _entries = entries
          .where((entry) => entry.filename != '.' && entry.filename != '..')
          .toList();
      _sortEntries();
    } on Object catch (error) {
      _error = '读取失败：$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sortEntries() {
    _entries.sort((a, b) {
      if (a.attr.isDirectory != b.attr.isDirectory)
        return a.attr.isDirectory ? -1 : 1;
      var result = switch (_sort) {
        _SortBy.name => a.filename.toLowerCase().compareTo(
          b.filename.toLowerCase(),
        ),
        _SortBy.size => (a.attr.size ?? 0).compareTo(b.attr.size ?? 0),
        _SortBy.time => (a.attr.modifyTime ?? 0).compareTo(
          b.attr.modifyTime ?? 0,
        ),
      };
      if (result == 0)
        result = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
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
      if (name != null)
        await _run(() => widget.sftp.mkdir(_join(_path.text, name)));
    } else {
      final result = await FilePicker.platform.pickFiles();
      final local = result?.files.single.path;
      if (local == null) return;
      await _run(() async {
        final source = File(local);
        final remotePath = _join(_path.text, path.basename(local));
        await _beginTransfer(
          '上传 ${path.basename(local)}',
          await source.length(),
          direction: 'upload',
          source: local,
          destination: remotePath,
        );
        final remote = await widget.sftp.open(
          remotePath,
          mode:
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate |
              SftpFileOpenMode.write,
        );
        try {
          await remote.write(_trackedRead(source)).done;
          if (_transferCancelled) {
            await widget.sftp.remove(remotePath);
            await _transferTracker?.cancel(_transferDone);
            throw StateError('上传已取消，远程临时文件已删除');
          }
          await _transferTracker?.complete(_transferDone);
        } finally {
          await remote.close();
          _endTransfer();
        }
      });
    }
    await _load();
  }

  Future<void> _entryAction(String action, SftpName entry) async {
    final remotePath = _join(_path.text, entry.filename);
    if (action == 'download') {
      final destination = await DownloadDestinationService.choose(
        fileName: entry.filename,
      );
      if (destination == null) return;
      await _run(() async {
        await _beginTransfer(
          '下载 ${entry.filename}',
          entry.attr.size ?? 0,
          direction: 'download',
          source: remotePath,
          destination: destination.path,
        );
        final remote = await widget.sftp.open(remotePath);
        final sink = destination.openWrite();
        try {
          await for (final chunk in remote.read()) {
            await _waitTransfer();
            if (_transferCancelled) break;
            sink.add(chunk);
            _advanceTransfer(chunk.length);
          }
          await sink.close();
          if (_transferCancelled) {
            await destination.delete();
            await _transferTracker?.cancel(_transferDone);
            throw StateError('下载已取消，未完成文件已删除');
          }
          await _transferTracker?.complete(_transferDone);
        } finally {
          await sink.close();
          await remote.close();
          _endTransfer();
        }
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedText('已下载到 ${destination.path}')),
        );
    } else if (action == 'rename') {
      final name = await _ask('重命名', '新名称', initial: entry.filename);
      if (name != null)
        await _run(
          () => widget.sftp.rename(remotePath, _join(_path.text, name)),
        );
    } else {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: LocalizedText('删除 ${entry.filename}？'),
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
      if (confirmed)
        await _run(
          () => entry.attr.isDirectory
              ? widget.sftp.rmdir(remotePath)
              : widget.sftp.remove(remotePath),
        );
    }
    await _load();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      await _transferTracker?.fail(_transferDone, error);
      _error = '操作失败：$error';
    }
    _transferTracker = null;
    if (mounted) setState(() => _loading = false);
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
    if (!mounted) return;
    setState(() => _transferDone += bytes);
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

  String _join(String base, String name) =>
      '${base.replaceAll(RegExp(r'/+$'), '')}/$name';
  String _time(int? seconds) => seconds == null
      ? '—'
      : DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
        ).toLocal().toString().substring(0, 16);
}
