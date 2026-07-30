import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:path/path.dart' as local_path;

import '../../../services/download_destination_service.dart';

enum _SortField { name, size, time }

class SftpBrowserPage extends StatefulWidget {
  const SftpBrowserPage({
    super.key,
    this.initialHost,
    this.initialPort = 22,
    this.initialUsername,
    this.initialPassword,
    this.autoConnect = false,
  });

  final String? initialHost;
  final int initialPort;
  final String? initialUsername;
  final String? initialPassword;
  final bool autoConnect;
  @override
  State<SftpBrowserPage> createState() => _SftpBrowserPageState();
}

class _SftpBrowserPageState extends State<SftpBrowserPage> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _password;
  final _path = TextEditingController(text: '/');
  SSHClient? _client;
  SftpClient? _sftp;
  List<SftpName> _entries = [];
  _SortField _sort = _SortField.name;
  bool _ascending = true;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.initialHost ?? '');
    _port = TextEditingController(text: '${widget.initialPort}');
    _user = TextEditingController(text: widget.initialUsername ?? 'root');
    _password = TextEditingController(text: widget.initialPassword ?? '');
    if (widget.autoConnect && _host.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
  }

  @override
  void dispose() {
    _client?.close();
    for (final controller in [_host, _port, _user, _password, _path]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('SFTP 文件')),
    body: _sftp == null ? _connectionForm() : _browser(),
  );

  Widget _connectionForm() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      TextField(
        controller: _host,
        decoration: const InputDecoration(label: LocalizedText('主机')),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _user,
              decoration: const InputDecoration(label: LocalizedText('用户名')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(label: LocalizedText('端口')),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(label: LocalizedText('密码')),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _busy ? null : _connect,
        icon: const Icon(Icons.login),
        label: const LocalizedText('连接 SFTP'),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_status.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: LocalizedText(_status),
        ),
    ],
  );

  Widget _browser() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(10),
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
                decoration: const InputDecoration(label: LocalizedText('远程路径')),
              ),
            ),
            IconButton(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              onSelected: _toolbarAction,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'upload', child: LocalizedText('上传文件')),
                PopupMenuItem(value: 'mkdir', child: LocalizedText('新建目录')),
              ],
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(child: _sortButton('名称', _SortField.name)),
            SizedBox(width: 90, child: _sortButton('大小', _SortField.size)),
            SizedBox(width: 110, child: _sortButton('修改时间', _SortField.time)),
          ],
        ),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_status.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: LocalizedText(_status),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: _entries.length,
          itemBuilder: (context, index) {
            final entry = _entries[index];
            final directory = entry.attr.isDirectory;
            final modified = entry.attr.modifyTime == null
                ? '—'
                : DateTime.fromMillisecondsSinceEpoch(
                    entry.attr.modifyTime! * 1000,
                  ).toLocal().toString().substring(0, 16);
            return ListTile(
              leading: Icon(
                directory ? Icons.folder : Icons.insert_drive_file_outlined,
              ),
              title: LocalizedText(entry.filename),
              subtitle: LocalizedText(
                directory ? '目录' : '${entry.attr.size ?? 0} B · $modified',
              ),
              onTap: directory
                  ? () {
                      _path.text = _remoteJoin(_path.text, entry.filename);
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
                  if (!directory)
                    const PopupMenuItem(
                      value: 'chmod',
                      child: LocalizedText('修改权限'),
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
  );

  Widget _sortButton(String text, _SortField field) => TextButton(
    onPressed: () => setState(() {
      if (_sort == field) {
        _ascending = !_ascending;
      } else {
        _sort = field;
        _ascending = true;
      }
      _sortEntries();
    }),
    child: LocalizedText(
      '$text${_sort == field ? (_ascending ? ' ▲' : ' ▼') : ''}',
    ),
  );

  Future<void> _connect() async {
    final port = int.tryParse(_port.text);
    if (_host.text.trim().isEmpty || port == null) return;
    setState(() {
      _busy = true;
      _status = '连接中…';
    });
    try {
      final client = SSHClient(
        await SSHSocket.connect(
          _host.text.trim(),
          port,
          timeout: const Duration(seconds: 10),
        ),
        username: _user.text.trim(),
        onPasswordRequest: () => _password.text,
      );
      await client.authenticated;
      _client = client;
      _sftp = await client.sftp();
      await _load();
    } on Object catch (error) {
      _client?.close();
      _client = null;
      _sftp = null;
      _status = '连接失败：$error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      final absolute = await _sftp!.absolute(_path.text.trim());
      final entries = await _sftp!.listdir(absolute);
      _path.text = absolute;
      _entries = entries
          .where((e) => e.filename != '.' && e.filename != '..')
          .toList();
      _sortEntries();
    } on Object catch (error) {
      _status = '读取目录失败：$error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sortEntries() {
    _entries.sort((a, b) {
      if (a.attr.isDirectory != b.attr.isDirectory)
        return a.attr.isDirectory ? -1 : 1;
      var value = switch (_sort) {
        _SortField.name => a.filename.toLowerCase().compareTo(
          b.filename.toLowerCase(),
        ),
        _SortField.size => (a.attr.size ?? 0).compareTo(b.attr.size ?? 0),
        _SortField.time => (a.attr.modifyTime ?? 0).compareTo(
          b.attr.modifyTime ?? 0,
        ),
      };
      if (value == 0)
        value = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      return _ascending ? value : -value;
    });
  }

  void _parent() {
    final value = _path.text.replaceAll(RegExp(r'/+$'), '');
    final slash = value.lastIndexOf('/');
    _path.text = slash <= 0 ? '/' : value.substring(0, slash);
    _load();
  }

  Future<void> _toolbarAction(String action) async {
    if (action == 'upload') {
      final picked = await FilePicker.platform.pickFiles(allowMultiple: false);
      final path = picked?.files.single.path;
      if (path == null) return;
      await _task('正在上传 ${local_path.basename(path)}…', () async {
        final remote = await _sftp!.open(
          _remoteJoin(_path.text, local_path.basename(path)),
          mode:
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate |
              SftpFileOpenMode.write,
        );
        try {
          await remote.write(File(path).openRead().cast()).done;
        } finally {
          await remote.close();
        }
      });
    } else {
      final name = await _ask('新建目录', '目录名称');
      if (name != null)
        await _task(
          '正在新建目录…',
          () => _sftp!.mkdir(_remoteJoin(_path.text, name)),
        );
    }
    await _load();
  }

  Future<void> _entryAction(String action, SftpName entry) async {
    final remotePath = _remoteJoin(_path.text, entry.filename);
    if (action == 'download') {
      final saveDialogTitle = context.tr('保存下载文件');
      final staging = await DownloadDestinationService.createStagingFile(
        fileName: entry.filename,
      );
      UserSavedFile? saved;
      await _task('正在下载…', () async {
        try {
          final remote = await _sftp!.open(remotePath);
          final sink = staging.openWrite();
          try {
            await sink.addStream(remote.read());
          } finally {
            await sink.close();
            await remote.close();
          }
          saved = await DownloadDestinationService.saveStagedFile(
            stagingFile: staging,
            fileName: entry.filename,
            dialogTitle: saveDialogTitle,
          );
        } finally {
          await DownloadDestinationService.discardStagingFile(staging);
        }
      });
      if (saved != null && mounted) {
        setState(() => _status = '已保存：${saved!.displayLocation}');
      }
    } else if (action == 'rename') {
      final name = await _ask('重命名', '新名称', initial: entry.filename);
      if (name != null)
        await _task(
          '正在重命名…',
          () => _sftp!.rename(remotePath, _remoteJoin(_path.text, name)),
        );
    } else if (action == 'chmod') {
      final value = await _ask('修改权限', '八进制权限，例如 0644', initial: '0644');
      if (value != null) {
        final mode = int.tryParse(value, radix: 8);
        if (mode == null) {
          setState(() => _status = '权限格式错误');
          return;
        }
        await _task(
          '正在修改权限…',
          () => _sftp!.setStat(
            remotePath,
            SftpFileAttrs(mode: SftpFileMode.value(mode)),
          ),
        );
      }
    } else if (action == 'delete') {
      final accepted =
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
      if (accepted)
        await _task(
          '正在删除…',
          () => entry.attr.isDirectory
              ? _sftp!.rmdir(remotePath)
              : _sftp!.remove(remotePath),
        );
    }
    await _load();
  }

  Future<void> _task(String status, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = status;
    });
    try {
      await action();
      _status = '操作完成';
    } on Object catch (error) {
      _status = '操作失败：$error';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<String?> _ask(
    String title,
    String label, {
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
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
    return value == null || value.isEmpty || value.contains('/') ? null : value;
  }

  String _remoteJoin(String base, String name) =>
      '${base.replaceAll(RegExp(r'/+$'), '')}/$name';
}
