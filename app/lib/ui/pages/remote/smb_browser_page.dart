import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as local_path;

import '../../../data/app_database.dart';
import '../../../services/download_destination_service.dart';
import '../../../services/network_defaults_service.dart';
import '../../../services/smb_service.dart';
import '../../../services/transfer_job_tracker.dart';
import '../../../state/app_state.dart';

enum _SmbSort { name, size, time }

class SmbBrowserPage extends StatefulWidget {
  const SmbBrowserPage({
    super.key,
    required this.appState,
    this.profile,
    this.initialHost,
    this.onLeave,
  });

  final AppState appState;
  final RemoteProfile? profile;
  final String? initialHost;
  final VoidCallback? onLeave;

  @override
  State<SmbBrowserPage> createState() => _SmbBrowserPageState();
}

class _SmbBrowserPageState extends State<SmbBrowserPage> {
  final _service = SmbService();
  final _storage = const FlutterSecureStorage();
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '445');
  final _share = TextEditingController();
  final _domain = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _path = TextEditingController();
  SmbConnectionInfo? _connection;
  List<SmbEntry> _entries = const [];
  _SmbSort _sort = _SmbSort.name;
  bool _ascending = true;
  bool _busy = false;
  bool _save = true;
  String? _status;
  String? _profileId;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    if (profile != null) {
      _profileId = profile.id;
      _name.text = profile.name;
      _host.text = profile.host;
      _port.text = '${profile.port}';
      _share.text = profile.shareName;
      _domain.text = profile.domain;
      _username.text = profile.username;
      _save = profile.secretRef != null;
    } else if (widget.initialHost?.trim().isNotEmpty == true) {
      _host.text = widget.initialHost!.trim();
    } else {
      NetworkDefaultsService().load().then((defaults) {
        if (mounted && _host.text.isEmpty && defaults.gateway != null)
          _host.text = defaults.gateway!;
      });
    }
  }

  @override
  void dispose() {
    final id = _connection?.sessionId;
    if (id != null) _service.disconnect(id);
    for (final controller in [
      _name,
      _host,
      _port,
      _share,
      _domain,
      _username,
      _password,
      _path,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: widget.onLeave == null
          ? null
          : IconButton(
              onPressed: widget.onLeave,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: context.tr('返回远程连接'),
            ),
      title: LocalizedText(
        _connection == null
            ? 'SMB2 / SMB3'
            : '\\\\${_host.text}\\${_share.text}',
      ),
      actions: [
        if (_connection != null)
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: context.tr('刷新'),
          ),
      ],
    ),
    body: _connection == null ? _connectionForm() : _browser(),
  );

  Widget _connectionForm() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
    children: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(label: LocalizedText('连接名称（可选）')),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _host,
              decoration: const InputDecoration(label: LocalizedText('主机')),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
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
        controller: _share,
        decoration: const InputDecoration(
          label: LocalizedText('共享名称'),
          helper: LocalizedText('例如 share、Downloads；服务端不允许枚举时必须手工填写'),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _domain,
              decoration: const InputDecoration(label: LocalizedText('域（可空）')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _username,
              decoration: const InputDecoration(
                label: LocalizedText('用户名（留空尝试 Guest）'),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: InputDecoration(
          label: LocalizedText('密码'),
          hintText: widget.profile?.secretRef == null
              ? null
              : context.tr('留空使用安全存储的密码'),
        ),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _save,
        onChanged: (value) => setState(() => _save = value ?? true),
        title: const LocalizedText('保存配置并用系统安全存储保护密码'),
      ),
      FilledButton.icon(
        onPressed: _busy || Platform.isLinux ? null : _connect,
        icon: const Icon(Icons.folder_shared),
        label: const LocalizedText('连接共享'),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_status != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SelectableText(context.tr(_status!)),
        ),
      const SizedBox(height: 12),
      LocalizedText(
        Platform.isWindows
            ? '仅支持 SMB2/SMB3。Windows 使用系统凭据管理器与 UNC，不把密码写入命令行。'
            : Platform.isLinux
            ? 'Linux 独立 SMB 会话尚未接入 libsmbclient；请先用桌面文件管理器挂载共享。'
            : '仅支持 SMB2/SMB3，不启用不安全的 SMB1。',
      ),
    ],
  );

  Widget _browser() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Row(
          children: [
            IconButton(
              onPressed: _busy ? null : _parent,
              icon: const Icon(Icons.arrow_upward),
              tooltip: context.tr('上级目录'),
            ),
            Expanded(
              child: TextField(
                controller: _path,
                onSubmitted: (_) => _load(),
                decoration: const InputDecoration(
                  label: LocalizedText('共享内路径'),
                ),
              ),
            ),
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: _toolbar,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'upload', child: LocalizedText('上传文件')),
                PopupMenuItem(value: 'mkdir', child: LocalizedText('新建目录')),
              ],
            ),
          ],
        ),
      ),
      Row(
        children: [
          Expanded(child: _sortButton('名称', _SmbSort.name)),
          SizedBox(width: 86, child: _sortButton('大小', _SmbSort.size)),
          SizedBox(width: 100, child: _sortButton('修改时间', _SmbSort.time)),
        ],
      ),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      if (_status != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: LocalizedText(_status!),
        ),
      Expanded(
        child: _entries.isEmpty && !_busy
            ? const Center(child: LocalizedText('目录为空'))
            : ListView.builder(
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return ListTile(
                    leading: Icon(
                      entry.directory
                          ? Icons.folder_rounded
                          : Icons.insert_drive_file_outlined,
                      color: entry.directory ? const Color(0xFF4A90E2) : null,
                    ),
                    title: LocalizedText(entry.name),
                    subtitle: entry.directory
                        ? const LocalizedText('目录')
                        : LocalizedText(
                            '${entry.size} B · ${_time(entry.modifiedMillis)}',
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
  );

  Widget _sortButton(String text, _SmbSort sort) => TextButton(
    onPressed: () => setState(() {
      if (_sort == sort) {
        _ascending = !_ascending;
      } else {
        _sort = sort;
        _ascending = true;
      }
      _sortEntries();
    }),
    child: LocalizedText(
      '$text${_sort == sort ? (_ascending ? ' ▲' : ' ▼') : ''}',
    ),
  );

  Future<void> _connect() async {
    final port = int.tryParse(_port.text);
    if (port == null ||
        _host.text.trim().isEmpty ||
        _share.text.trim().isEmpty) {
      setState(() => _status = '请填写有效主机、端口和共享名称');
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在协商 SMB2/SMB3…';
    });
    try {
      _profileId ??=
          'smb_${DateTime.now().microsecondsSinceEpoch}_${_host.text.hashCode.abs()}';
      final secretRef = widget.profile?.secretRef ?? 'smb-profile:$_profileId';
      var password = _password.text;
      if (password.isEmpty) {
        final stored = await _storage.read(key: secretRef);
        if (stored != null)
          password =
              (jsonDecode(stored) as Map<String, Object?>)['password']
                  as String? ??
              '';
      }
      final result = await _service.connect(
        host: _host.text.trim(),
        port: port,
        share: _share.text.trim(),
        username: _username.text.trim(),
        password: password,
        domain: _domain.text.trim(),
      );
      String? savedSecret;
      if (_save) {
        await _storage.write(
          key: secretRef,
          value: jsonEncode({'password': password}),
        );
        savedSecret = secretRef;
      }
      final now = DateTime.now();
      await widget.appState.database.putRemoteProfile(
        RemoteProfilesCompanion.insert(
          id: _profileId!,
          name: _name.text.trim().isEmpty
              ? '\\\\${_host.text}\\${_share.text}'
              : _name.text.trim(),
          protocol: 'smb',
          host: _host.text.trim(),
          port: port,
          username: Value(_username.text.trim()),
          domain: Value(_domain.text.trim()),
          shareName: Value(_share.text.trim()),
          authType: const Value('password'),
          secretRef: Value(savedSecret),
          createdAt: widget.profile?.createdAt ?? now,
          updatedAt: now,
        ),
      );
      _connection = result;
      _status = '${result.dialect}${result.guest ? ' · Guest' : ''}';
      await _load();
    } on Object catch (error) {
      _status = '连接失败：$error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async => _task('正在读取目录…', () async {
    _entries = await _service.list(_connection!.sessionId, _path.text.trim());
    _sortEntries();
  }, success: null);

  void _sortEntries() => _entries.sort((a, b) {
    if (a.directory != b.directory) return a.directory ? -1 : 1;
    var result = switch (_sort) {
      _SmbSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      _SmbSort.size => a.size.compareTo(b.size),
      _SmbSort.time => a.modifiedMillis.compareTo(b.modifiedMillis),
    };
    if (result == 0)
      result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return _ascending ? result : -result;
  });

  void _parent() {
    final value = _path.text
        .replaceAll('/', '\\')
        .replaceAll(RegExp(r'\\+$'), '');
    final slash = value.lastIndexOf('\\');
    _path.text = slash < 0 ? '' : value.substring(0, slash);
    _load();
  }

  Future<void> _toolbar(String action) async {
    if (action == 'mkdir') {
      final name = await _ask('新建目录', '目录名称');
      if (name != null)
        await _task(
          '正在新建目录…',
          () => _service.mkdir(_connection!.sessionId, _join(_path.text, name)),
        );
    } else {
      final picked = await FilePicker.platform.pickFiles();
      final local = picked?.files.single.path;
      if (local == null) return;
      await _task('正在上传 ${local_path.basename(local)}…', () async {
        final remote = _join(_path.text, local_path.basename(local));
        await _trackedTransfer(
          direction: 'upload',
          source: local,
          destination: remote,
          total: await File(local).length(),
          action: () => _service.upload(_connection!.sessionId, local, remote),
        );
      });
    }
    await _load();
  }

  Future<void> _entryAction(String action, SmbEntry entry) async {
    final remote = _join(_path.text, entry.name);
    if (action == 'download') {
      final destination = await DownloadDestinationService.choose(
        fileName: entry.name,
      );
      if (destination == null) return;
      final target = destination.path;
      await _task('正在下载…', () async {
        await _trackedTransfer(
          direction: 'download',
          source: remote,
          destination: target,
          total: entry.size,
          action: () =>
              _service.download(_connection!.sessionId, remote, target),
        );
      }, success: '已下载到 $target');
    } else if (action == 'rename') {
      final name = await _ask('重命名', '新名称', initial: entry.name);
      if (name != null)
        await _task(
          '正在重命名…',
          () => _service.rename(
            _connection!.sessionId,
            remote,
            _join(_path.text, name),
          ),
        );
    } else {
      final accepted =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: LocalizedText('删除 ${entry.name}？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const LocalizedText('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const LocalizedText('删除'),
                ),
              ],
            ),
          ) ??
          false;
      if (accepted)
        await _task(
          '正在删除…',
          () => _service.delete(
            _connection!.sessionId,
            remote,
            directory: entry.directory,
          ),
        );
    }
    await _load();
  }

  Future<void> _task(
    String status,
    Future<void> Function() action, {
    String? success = '操作完成',
  }) async {
    if (mounted)
      setState(() {
        _busy = true;
        _status = status;
      });
    try {
      await action();
      _status = success;
    } on Object catch (error) {
      _status = '操作失败：$error';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _trackedTransfer({
    required String direction,
    required String source,
    required String destination,
    required int total,
    required Future<int> Function() action,
  }) async {
    final tracker = TransferJobTracker(
      database: widget.appState.database,
      profileId: _profileId ?? 'temporary-smb',
      direction: direction,
      sourcePath: source,
      destinationPath: destination,
      totalBytes: total,
    );
    await tracker.start();
    try {
      final bytes = await action();
      await tracker.complete(bytes);
    } on Object catch (error) {
      await tracker.fail(0, error);
      rethrow;
    }
  }

  Future<String?> _ask(
    String title,
    String label, {
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: LocalizedText(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const LocalizedText('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value == null || value.isEmpty || value.contains(RegExp(r'[\\/]'))
        ? null
        : value;
  }

  String _join(String base, String name) => base.trim().isEmpty
      ? name
      : '${base.replaceAll('/', '\\').replaceAll(RegExp(r'\\+$'), '')}\\$name';
  String _time(int millis) => millis <= 0
      ? '—'
      : DateTime.fromMillisecondsSinceEpoch(
          millis,
        ).toLocal().toString().substring(0, 16);
}
