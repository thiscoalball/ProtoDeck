import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:xterm/xterm.dart';
import '../../../data/app_database.dart';
import '../../../state/app_state.dart';
import '../../../services/network_defaults_service.dart';
import '../../../services/terminal_ansi_colorizer.dart';
import '../../widgets/ssh/ssh_terminal_surface.dart';
import 'embedded_sftp_panel.dart';
import 'embedded_ssh_file_panel.dart';

class SshTerminalPage extends StatefulWidget {
  const SshTerminalPage({
    super.key,
    required this.appState,
    this.initialHost,
    this.profile,
    this.autoConnect = false,
    this.onLeave,
  });
  final AppState appState;
  final String? initialHost;
  final RemoteProfile? profile;
  final bool autoConnect;
  final VoidCallback? onLeave;
  @override
  State<SshTerminalPage> createState() => _SshTerminalPageState();
}

class _SshTerminalPageState extends State<SshTerminalPage> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController(text: 'root');
  final _profileName = TextEditingController();
  final _password = TextEditingController();
  final _passphrase = TextEditingController();
  final _terminal = Terminal(maxLines: 10000);
  final _terminalColorizer = TerminalAnsiColorizer();
  final _terminalFocus = FocusNode(debugLabel: 'ssh-terminal-input');
  final _storage = const FlutterSecureStorage();
  SSHClient? _client;
  SSHClient? _browserClient;
  SSHSession? _session;
  SftpClient? _sftp;
  bool _connecting = false, _connected = false, _save = true;
  bool _saveProfile = true;
  String _authType = 'password';
  String? _privateKeyPem;
  String? _privateKeyName;
  String? _profileId;
  bool _showFiles = false;
  bool _shellBrowserReady = false;
  String _sftpStage = '未初始化';
  String? _sftpError;
  String? _authPassword;
  String? _authPrivateKey;
  String? _authPassphrase;
  int? _connectedPort;
  String? _error;
  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    if (profile != null) {
      _profileId = profile.id;
      _profileName.text = profile.name;
      _host.text = profile.host;
      _port.text = '${profile.port}';
      _user.text = profile.username;
      _authType = profile.authType;
      _save = profile.secretRef != null;
      if (widget.autoConnect && profile.secretRef != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_connected && !_connecting) _connect();
        });
      }
      return;
    }
    final initialHost = widget.initialHost?.trim();
    if (initialHost?.isNotEmpty == true) {
      _host.text = initialHost!;
      return;
    }
    NetworkDefaultsService().load().then((defaults) {
      if (mounted && _host.text.isEmpty && defaults.gateway != null) {
        _host.text = defaults.gateway!;
      }
    });
  }

  @override
  void dispose() {
    _session?.close();
    _sftp?.close();
    _browserClient?.close();
    _client?.close();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _profileName.dispose();
    _password.dispose();
    _passphrase.dispose();
    _terminalFocus.dispose();
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
        _connected ? '${_user.text}@${_host.text}' : 'SSH 终端',
      ),
      actions: [
        if (_connected)
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 11),
            ),
            onPressed: () => setState(() => _showFiles = !_showFiles),
            icon: Icon(_showFiles ? Icons.terminal : Icons.folder_open),
            label: LocalizedText(_showFiles ? '终端' : '文件'),
          ),
        if (_connected)
          IconButton(
            onPressed: _disconnect,
            icon: const Icon(Icons.link_off),
            tooltip: context.tr('断开'),
          ),
      ],
    ),
    body: _connected
        ? _connectedBody()
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _profileName,
                decoration: const InputDecoration(
                  label: LocalizedText('连接名称（可选）'),
                  hint: LocalizedText('例如：客厅路由器'),
                ),
              ),
              const SizedBox(height: 10),
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
                      decoration: const InputDecoration(
                        label: LocalizedText('用户名'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        label: LocalizedText('端口'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'password',
                    icon: Icon(Icons.password),
                    label: LocalizedText('密码'),
                  ),
                  ButtonSegment(
                    value: 'privateKey',
                    icon: Icon(Icons.key),
                    label: LocalizedText('私钥'),
                  ),
                ],
                selected: {_authType},
                onSelectionChanged: (value) =>
                    setState(() => _authType = value.first),
              ),
              const SizedBox(height: 10),
              if (_authType == 'password')
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    label: LocalizedText('密码'),
                    hintText: widget.profile?.secretRef != null
                        ? '留空使用已安全保存的密码'
                        : null,
                  ),
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: _pickPrivateKey,
                  icon: const Icon(Icons.file_open),
                  label: LocalizedText(
                    _privateKeyName ?? '选择 OpenSSH / PEM 私钥',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passphrase,
                  obscureText: true,
                  decoration: InputDecoration(
                    label: LocalizedText('私钥口令（可选）'),
                    hintText: widget.profile?.secretRef != null
                        ? '留空使用已安全保存的私钥与口令'
                        : null,
                  ),
                ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _saveProfile,
                onChanged: (v) => setState(() => _saveProfile = v ?? true),
                title: const LocalizedText('保存连接配置'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _save,
                onChanged: (v) => setState(() => _save = v ?? true),
                title: LocalizedText(
                  _authType == 'password' ? '使用系统安全存储保护密码' : '使用系统安全存储保护私钥与口令',
                ),
              ),
              FilledButton.icon(
                onPressed: _connecting ? null : _connect,
                icon: const Icon(Icons.login),
                label: LocalizedText(_connecting ? '连接中…' : '连接'),
              ),
              if (_connecting) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LocalizedText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const LocalizedText(
                '首次连接会显示主机密钥指纹并要求确认；已信任主机的指纹变化时连接会被阻止。终端内容默认不写入历史。',
              ),
            ],
          ),
  );
  Future<void> _connect() async {
    final port = int.tryParse(_port.text);
    if (_host.text.trim().isEmpty || port == null) {
      setState(() => _error = '请输入有效主机和端口');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final endpoint = '${_host.text.trim()}:$port';
    try {
      _profileId ??=
          'ssh_${DateTime.now().microsecondsSinceEpoch}_${endpoint.hashCode.abs()}';
      final secretKey = widget.profile?.secretRef ?? 'ssh-profile:$_profileId';
      var password = _password.text;
      var privateKey = _privateKeyPem;
      var passphrase = _passphrase.text;
      final stored = await _storage.read(key: secretKey);
      if (stored != null && stored.isNotEmpty) {
        try {
          final decoded = jsonDecode(stored) as Map<String, Object?>;
          if (password.isEmpty) password = decoded['password'] as String? ?? '';
          privateKey ??= decoded['privateKey'] as String?;
          if (passphrase.isEmpty) {
            passphrase = decoded['passphrase'] as String? ?? '';
          }
        } on FormatException {
          // Migrate credentials saved by the earlier password-only build.
          if (password.isEmpty) password = stored;
        }
      }
      final identities = _authType == 'privateKey'
          ? _parseIdentities(privateKey, passphrase)
          : null;
      if (_save && _authType == 'password' && password.isEmpty) {
        throw StateError('密码不能为空');
      }
      if (_save && _authType == 'privateKey' && privateKey == null) {
        throw StateError('请选择有效的私钥文件');
      }
      _authPassword = password;
      _authPrivateKey = privateKey;
      _authPassphrase = passphrase;
      _connectedPort = port;
      final socket = await SSHSocket.connect(
        _host.text.trim(),
        port,
        timeout: const Duration(seconds: 10),
      );
      final client = SSHClient(
        socket,
        username: _user.text.trim(),
        onPasswordRequest: _authType == 'password' ? () => password : null,
        identities: identities,
        onVerifyHostKey: (algorithm, fingerprint) =>
            _verify(endpoint, algorithm, base64Encode(fingerprint)),
      );
      await client.authenticated;
      final session = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: _terminal.viewWidth,
          height: _terminal.viewHeight,
        ),
      );
      _client = client;
      _session = session;
      _sftpError = null;
      _terminal.onOutput = (data) => session.write(utf8.encode(data));
      _terminal.onResize = (w, h, pw, ph) =>
          session.resizeTerminal(w, h, pw, ph);
      session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) => _terminal.write(_terminalColorizer.colorize(data)));
      session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) => _terminal.write(_terminalColorizer.colorize(data)));
      session.done.whenComplete(
        () => mounted ? setState(() => _connected = false) : null,
      );
      if (mounted) {
        setState(() {
          _connected = true;
          // The shell is usable immediately. File browsing initializes on a
          // separate SSH channel and must never block terminal input.
          _showFiles = false;
          _sftpStage = '正在建立 SSH 文件通道…';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _terminalFocus.requestFocus();
        });
      }
      unawaited(
        _startFileBrowser(
          password: password,
          privateKey: privateKey,
          passphrase: passphrase,
          endpoint: endpoint,
          port: port,
        ),
      );
      try {
        String? savedSecretRef;
        if (_save) {
          await _storage.write(
            key: secretKey,
            value: jsonEncode({
              'authType': _authType,
              'password': _authType == 'password' ? password : null,
              'privateKey': _authType == 'privateKey' ? privateKey : null,
              'passphrase': _authType == 'privateKey' ? passphrase : null,
            }),
          );
          savedSecretRef = secretKey;
        } else if (widget.profile?.secretRef != null) {
          await _storage.delete(key: widget.profile!.secretRef!);
        }
        if (_saveProfile) {
          final now = DateTime.now();
          await widget.appState.database.putRemoteProfile(
            RemoteProfilesCompanion.insert(
              id: _profileId!,
              name: _profileName.text.trim().isEmpty
                  ? '${_user.text.trim()}@${_host.text.trim()}'
                  : _profileName.text.trim(),
              protocol: 'ssh',
              host: _host.text.trim(),
              port: port,
              username: Value(_user.text.trim()),
              authType: Value(_authType),
              secretRef: Value(savedSecretRef),
              createdAt: widget.profile?.createdAt ?? now,
              updatedAt: now,
            ),
          );
        }
      } on Object catch (error) {
        // Credential/profile persistence is secondary. A successful SSH
        // session must remain usable even if Windows Credential Manager or
        // the local profile database is unavailable.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: LocalizedText('已连接，但保存配置失败：$error')),
          );
        }
      }
    } on Object catch (e) {
      _sftp?.close();
      _browserClient?.close();
      _client?.close();
      _sftp = null;
      _browserClient = null;
      _client = null;
      setState(() => _error = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _startFileBrowser({
    required String password,
    required String? privateKey,
    required String passphrase,
    required String endpoint,
    required int port,
  }) async {
    try {
      await _initializeFileBrowser(
        password: password,
        privateKey: privateKey,
        passphrase: passphrase,
        endpoint: endpoint,
        port: port,
      );
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _sftpError = '$error';
          _sftpStage = '文件通道未就绪，终端仍可正常使用';
        });
      }
    }
  }

  Future<bool> _verify(
    String endpoint,
    String algorithm,
    String fingerprint,
  ) async {
    final db = widget.appState.database;
    final old = await (db.select(
      db.knownHosts,
    )..where((r) => r.endpoint.equals(endpoint))).getSingleOrNull();
    if (old != null)
      return old.algorithm == algorithm && old.fingerprint == fingerprint;
    if (!mounted) return false;
    final accepted =
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const LocalizedText('首次连接主机'),
            content: SelectableText(
              '$endpoint\n$algorithm\nSHA256:$fingerprint',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const LocalizedText('拒绝'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const LocalizedText('信任并连接'),
              ),
            ],
          ),
        ) ??
        false;
    if (accepted)
      await db
          .into(db.knownHosts)
          .insert(
            KnownHostsCompanion.insert(
              endpoint: endpoint,
              algorithm: algorithm,
              fingerprint: fingerprint,
              trustedAt: DateTime.now(),
            ),
          );
    return accepted;
  }

  void _disconnect() {
    _session?.close();
    _sftp?.close();
    _browserClient?.close();
    _client?.close();
    _sftp = null;
    _browserClient = null;
    _shellBrowserReady = false;
    _authPassword = null;
    _authPrivateKey = null;
    _authPassphrase = null;
    _connectedPort = null;
    setState(() {
      _connected = false;
      _showFiles = false;
      _sftpStage = '未初始化';
    });
  }

  Future<void> _initializeFileBrowser({
    required String password,
    required String? privateKey,
    required String passphrase,
    required String endpoint,
    required int port,
  }) async {
    _sftp?.close();
    _browserClient?.close();
    _sftp = null;
    _browserClient = null;
    _shellBrowserReady = false;
    if (mounted) setState(() => _sftpStage = '正在建立 SSH 文件通道…');
    final socket = await SSHSocket.connect(
      _host.text.trim(),
      port,
      timeout: const Duration(seconds: 10),
    );
    final browserClient = SSHClient(
      socket,
      username: _user.text.trim(),
      onPasswordRequest: _authType == 'password' ? () => password : null,
      identities: _authType == 'privateKey'
          ? _parseIdentities(privateKey, passphrase)
          : null,
      onVerifyHostKey: (algorithm, fingerprint) =>
          _verify(endpoint, algorithm, base64Encode(fingerprint)),
    );
    await browserClient.authenticated;
    _browserClient = browserClient;
    try {
      await _initializeSftp(browserClient);
    } on Object catch (error) {
      _sftpError = '$error';
      if (mounted) {
        setState(() => _sftpStage = 'SFTP 不可用，正在切换 SCP/Shell 模式…');
      }
      final home = utf8.decode(
        await browserClient.run('pwd').timeout(const Duration(seconds: 6)),
      );
      if (home.trim().isEmpty) {
        throw StateError('路由器未返回可浏览的初始目录');
      }
      _shellBrowserReady = true;
      if (mounted) setState(() => _sftpStage = 'SSH Browser 已就绪（SCP/Shell）');
    }
  }

  Future<void> _initializeSftp(SSHClient client) async {
    if (mounted) setState(() => _sftpStage = '正在请求 sftp subsystem…');
    SftpClient? sftp;
    try {
      sftp = await client.sftp();
      if (mounted) setState(() => _sftpStage = '正在协商 SFTP 版本…');
      // client.sftp() creates the SSH channel, while handshake confirms that
      // the server actually accepted and started the SFTP subsystem.
      await sftp.handshake.timeout(const Duration(seconds: 2));
      _sftp = sftp;
      _sftpError = null;
      if (mounted) setState(() => _sftpStage = 'SFTP 已就绪');
    } on Object {
      sftp?.close();
      if (mounted) setState(() => _sftpStage = 'SFTP 子系统启动失败');
      rethrow;
    }
  }

  Future<void> _retryFileBrowser() async {
    final password = _authPassword;
    final port = _connectedPort;
    if (password == null || port == null) return;
    setState(() => _sftpError = null);
    try {
      await _initializeFileBrowser(
        password: password,
        privateKey: _authPrivateKey,
        passphrase: _authPassphrase ?? '',
        endpoint: '${_host.text.trim()}:$port',
        port: port,
      );
      if (mounted) setState(() => _showFiles = true);
    } on Object catch (error) {
      if (mounted) setState(() => _sftpError = '$error');
    }
  }

  List<SSHKeyPair> _parseIdentities(String? pem, String passphrase) {
    if (pem == null || pem.trim().isEmpty) {
      throw const FormatException('请选择 OpenSSH 或 PEM 私钥');
    }
    try {
      final identities = SSHKeyPair.fromPem(
        pem,
        passphrase.isEmpty ? null : passphrase,
      );
      if (identities.isEmpty) throw const FormatException('文件中没有可用私钥');
      return identities;
    } on Object catch (error) {
      throw FormatException('私钥解析失败：$error');
    }
  }

  Future<void> _pickPrivateKey() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.single;
    if (file == null) return;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = '无法读取私钥文件');
      return;
    }
    if (bytes.length > 1024 * 1024) {
      setState(() => _error = '私钥文件异常大（超过 1 MiB）');
      return;
    }
    setState(() {
      _privateKeyPem = utf8.decode(bytes, allowMalformed: false);
      _privateKeyName = file.name;
      _error = null;
    });
  }

  Widget _connectedBody() => LayoutBuilder(
    builder: (context, constraints) {
      final terminal = SshTerminalSurface(
        terminal: _terminal,
        focusNode: _terminalFocus,
        onSend: (data) => _session?.write(utf8.encode(data)),
      );
      final sftp = _sftp;
      final browserClient = _browserClient;
      final files = sftp != null
          ? EmbeddedSftpPanel(
              sftp: sftp,
              database: widget.appState.database,
              profileId: _profileId ?? 'temporary-ssh',
            )
          : browserClient != null && _shellBrowserReady
          ? EmbeddedSshFilePanel(
              client: browserClient,
              database: widget.appState.database,
              profileId: _profileId ?? 'temporary-ssh',
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_off_outlined, size: 42),
                    const SizedBox(height: 10),
                    LocalizedText('SSH 文件浏览通道未就绪', textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    LocalizedText(_sftpStage, textAlign: TextAlign.center),
                    if (_sftpError != null) ...[
                      const SizedBox(height: 6),
                      SelectableText(
                        _sftpError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _retryFileBrowser,
                      icon: const Icon(Icons.refresh),
                      label: const LocalizedText('重试文件通道'),
                    ),
                  ],
                ),
              ),
            );
      if (constraints.maxWidth >= 760) {
        return Row(
          children: [
            SizedBox(width: 350, child: files),
            const VerticalDivider(width: 1),
            Expanded(child: terminal),
          ],
        );
      }
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.terminal),
                    label: LocalizedText('终端'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.folder_open),
                    label: LocalizedText('远程文件'),
                  ),
                ],
                selected: {_showFiles},
                onSelectionChanged: (value) =>
                    setState(() => _showFiles = value.first),
              ),
            ),
          ),
          Expanded(child: _showFiles ? files : terminal),
        ],
      );
    },
  );
}
