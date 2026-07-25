import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../services/local_test_server_service.dart';
import '../../../services/native_network_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class LocalTestServerPage extends StatefulWidget {
  const LocalTestServerPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<LocalTestServerPage> createState() => _LocalTestServerPageState();
}

class _LocalTestServerPageState extends State<LocalTestServerPage> {
  final _service = LocalTestServerService.instance;
  final _native = NativeNetworkService();
  final _port = TextEditingController(text: '8080');
  final _response = TextEditingController(text: 'Hello from local test server');
  final _contentType = TextEditingController(text: 'text/plain; charset=utf-8');
  final _statusCode = TextEditingController(text: '200');
  final _responseHeaders = TextEditingController();
  StreamSubscription<LocalTestServerSnapshot>? _subscription;
  late LocalTestServerSnapshot _snapshot;
  var _selectedMode = LocalTestServerMode.http;
  var _addresses = <String>[];
  var _loadingAddresses = false;
  var _busy = false;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    for (final controller in [
      _port,
      _response,
      _contentType,
      _statusCode,
      _responseHeaders,
    ]) {
      controller.addListener(_saveDraft);
    }
    _snapshot = _service.snapshot;
    if (_snapshot.running) {
      _selectedMode = _snapshot.mode;
      _port.text = '${_snapshot.port}';
    }
    _subscription = _service.changes.listen((value) {
      if (!mounted) return;
      setState(() {
        _snapshot = value;
        if (value.running) {
          _selectedMode = value.mode;
          _port.text = '${value.port}';
        }
      });
    });
    unawaited(_restoreDraftAndLoadAddresses());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_draftLoaded) {
      unawaited(_drafts.save('tool.local_server', _draftValue()));
    }
    _drafts.dispose();
    _port.dispose();
    _response.dispose();
    _contentType.dispose();
    _statusCode.dispose();
    _responseHeaders.dispose();
    // The listener intentionally survives page navigation. It is stopped only
    // through the visible Stop action or when the app process terminates.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _snapshot.running;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('本地测试服务'),
        actions: [
          IconButton.filledTonal(
            onPressed: _snapshot.events.isEmpty ? null : _service.clearEvents,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: context.tr('清空事件'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _statusCard(context),
          const SizedBox(height: 18),
          LocalizedText('服务类型', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SegmentedButton<LocalTestServerMode>(
            segments: const [
              ButtonSegment(
                value: LocalTestServerMode.http,
                icon: Icon(Icons.http),
                label: LocalizedText('HTTP'),
              ),
              ButtonSegment(
                value: LocalTestServerMode.tcpEcho,
                icon: Icon(Icons.swap_horiz),
                label: LocalizedText('TCP Echo'),
              ),
            ],
            selected: {_selectedMode},
            onSelectionChanged: running || _busy
                ? null
                : (value) {
                    setState(() {
                      _selectedMode = value.first;
                      if (_selectedMode == LocalTestServerMode.http &&
                          _port.text == '9000') {
                        _port.text = '8080';
                      } else if (_selectedMode == LocalTestServerMode.tcpEcho &&
                          _port.text == '8080') {
                        _port.text = '9000';
                      }
                    });
                    _saveDraft();
                  },
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _port,
                    enabled: !running && !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      label: LocalizedText('监听端口'),
                      prefixIcon: Icon(Icons.settings_ethernet),
                      helper: LocalizedText('访问此服务的客户端需要使用相同端口'),
                    ),
                  ),
                  if (_selectedMode == LocalTestServerMode.http) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 112,
                          child: TextField(
                            controller: _statusCode,
                            enabled: !running && !_busy,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              label: LocalizedText('状态码'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _contentType,
                            enabled: !running && !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Content-Type',
                              prefixIcon: Icon(Icons.description_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _responseHeaders,
                      enabled: !running && !_busy,
                      minLines: 2,
                      maxLines: 5,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        label: LocalizedText('自定义响应头（每行一个）'),
                        hintText: 'X-Test-Node: phone',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _response,
                      enabled: !running && !_busy,
                      minLines: 3,
                      maxLines: 7,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        label: LocalizedText('固定响应正文'),
                        alignLabelWithHint: true,
                        hint: LocalizedText('输入访问该服务时返回的内容'),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    const _InfoRow(
                      icon: Icons.sync_alt,
                      title: '原样回显',
                      detail: '每个 TCP 客户端发送的字节都会原样写回，可用于验证双向收发。',
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: running
                        ? FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onError,
                            ),
                            onPressed: _busy ? null : _stop,
                            icon: const Icon(Icons.stop_rounded),
                            label: const LocalizedText('停止服务'),
                          )
                        : FilledButton.icon(
                            onPressed: _busy ? null : _confirmAndStart,
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow_rounded),
                            label: LocalizedText(_busy ? '正在启动' : '启动服务'),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _endpointSection(context),
          const SizedBox(height: 18),
          _usageGuide(context),
          const SizedBox(height: 18),
          _eventSection(context),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (_snapshot.status) {
      LocalTestServerStatus.stopped => (
        '未启动',
        Icons.power_settings_new,
        scheme.onSurfaceVariant,
      ),
      LocalTestServerStatus.starting => (
        '正在启动',
        Icons.hourglass_top,
        scheme.primary,
      ),
      LocalTestServerStatus.listening => (
        '正在监听',
        Icons.check_circle,
        const Color(0xFF159A6C),
      ),
      LocalTestServerStatus.stopping => (
        '正在停止',
        Icons.hourglass_bottom,
        const Color(0xFFD38118),
      ),
      LocalTestServerStatus.failed => ('启动失败', Icons.error, scheme.error),
    };
    final modeLabel = _snapshot.mode == LocalTestServerMode.http
        ? 'HTTP Server'
        : 'TCP Echo Server';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: .72),
            scheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.dns_outlined, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      _snapshot.running ? modeLabel : '手机端口监听器',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    LocalizedText(
                      _snapshot.running
                          ? '${_snapshot.bindAddress}:${_snapshot.port}'
                          : '快速在手机上提供可访问的测试端点',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 5),
                    LocalizedText(
                      label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_snapshot.running) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: _snapshot.mode == LocalTestServerMode.http
                        ? '请求'
                        : '连接',
                    value: _snapshot.mode == LocalTestServerMode.http
                        ? '${_snapshot.requestCount}'
                        : '${_snapshot.connectionCount}',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '接收',
                    value: _formatBytes(_snapshot.receivedBytes),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '发送',
                    value: _formatBytes(_snapshot.sentBytes),
                  ),
                ),
                if (_snapshot.mode == LocalTestServerMode.tcpEcho)
                  Expanded(
                    child: _Metric(
                      label: '在线',
                      value: '${_snapshot.activeConnections}',
                    ),
                  ),
              ],
            ),
          ],
          if (_snapshot.error != null) ...[
            const SizedBox(height: 12),
            LocalizedText(
              _snapshot.error!,
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _endpointSection(BuildContext context) {
    final running = _snapshot.running;
    final addresses = _addresses;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: LocalizedText(
                '局域网访问地址',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: _loadingAddresses ? null : _loadAddresses,
              icon: _loadingAddresses
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: const LocalizedText('刷新'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (addresses.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: _InfoRow(
                icon: Icons.wifi_off_outlined,
                title: '暂未获取到局域网 IPv4 地址',
                detail: '请先连接 Wi‑Fi，再刷新地址。服务仍可监听，但其他设备需要一个可达的手机地址。',
              ),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < addresses.length; index++) ...[
                  _endpointTile(addresses[index], running),
                  if (index != addresses.length - 1)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        LocalizedText(
          running
              ? '服务绑定全部 IPv4 接口。其他设备可使用上方 Wi‑Fi 地址和端口访问。'
              : '启动后会在这里生成可复制的目标地址。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _endpointTile(String address, bool running) {
    final endpoint = _selectedMode == LocalTestServerMode.http
        ? 'http://$address:${_snapshot.running ? _snapshot.port : _port.text}/'
        : '$address:${_snapshot.running ? _snapshot.port : _port.text}';
    return ListTile(
      leading: Icon(
        _selectedMode == LocalTestServerMode.http
            ? Icons.language
            : Icons.settings_ethernet,
      ),
      title: LocalizedText(
        endpoint,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
      subtitle: LocalizedText(running ? '局域网设备可访问' : '启动后可用'),
      trailing: IconButton.filledTonal(
        onPressed: running ? () => _copy(endpoint) : null,
        icon: const Icon(Icons.copy, size: 19),
        tooltip: context.tr('复制地址'),
      ),
    );
  }

  Widget _usageGuide(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalizedText('使用说明', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const _Step(
            number: '1',
            title: '启动手机服务',
            detail: '选择 HTTP 或 TCP Echo，填写端口并确认服务显示“正在监听”。',
          ),
          const _Step(
            number: '2',
            title: '从其他设备访问',
            detail: '保持设备处于同一局域网，使用上方手机 IP 和监听端口建立连接。',
          ),
          const _Step(
            number: '3',
            title: '检查实时事件',
            detail: '下方出现 HTTP 请求或 TCP 连接事件，即表示访问已抵达手机服务。',
            last: true,
          ),
        ],
      ),
    ),
  );

  Widget _eventSection(BuildContext context) {
    final events = _snapshot.events;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            LocalizedText(
              '实时事件',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            LocalizedText(
              '${events.length} 条',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Center(child: LocalizedText('请求或连接到达后，会实时显示在这里')),
            ),
          )
        else
          ...events.map((event) => _eventTile(context, event)),
      ],
    );
  }

  Widget _eventTile(BuildContext context, LocalTestServerEvent event) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (event.kind) {
      'HTTP' || 'ECHO' => const Color(0xFF159A6C),
      'ERR' => scheme.error,
      'WARN' => const Color(0xFFD38118),
      'OPEN' => scheme.primary,
      _ => scheme.onSurfaceVariant,
    };
    final header = Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .11),
            borderRadius: BorderRadius.circular(8),
          ),
          child: LocalizedText(
            event.kind,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LocalizedText(
            event.peer,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        LocalizedText(
          DateFormat('HH:mm:ss').format(event.time),
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
    if (event.detail == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 8),
              LocalizedText(event.summary),
            ],
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 8),
            LocalizedText(event.summary),
          ],
        ),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 4),
          child: LocalizedText('点击查看请求详情'),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              event.detail!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndStart() async {
    final port = int.tryParse(_port.text);
    if (port == null || port < 1 || port > 65535) {
      _message('请输入 1～65535 的有效监听端口');
      return;
    }
    if (_selectedMode == LocalTestServerMode.http &&
        _contentType.text.trim().isEmpty) {
      _message('请输入有效的 HTTP Content-Type');
      return;
    }
    final statusCode = int.tryParse(_statusCode.text);
    if (_selectedMode == LocalTestServerMode.http &&
        (statusCode == null || statusCode < 100 || statusCode > 599)) {
      _message('请输入 100～599 的 HTTP 状态码');
      return;
    }
    final responseHeaders = <String, String>{};
    if (_selectedMode == LocalTestServerMode.http) {
      for (final line in _responseHeaders.text.split('\n')) {
        if (line.trim().isEmpty) continue;
        final separator = line.indexOf(':');
        if (separator <= 0) {
          _message('响应头格式错误：$line');
          return;
        }
        responseHeaders[line.substring(0, separator).trim()] = line
            .substring(separator + 1)
            .trim();
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: const LocalizedText('允许局域网设备访问？'),
        content: const LocalizedText(
          '服务将绑定 0.0.0.0，对当前网络中的设备开放。请仅在可信网络中使用，并在测试完成后停止服务。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('确认启动'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _service.start(
        mode: _selectedMode,
        port: port,
        httpResponseBody: _response.text,
        httpContentType: _contentType.text.trim(),
        httpStatusCode: statusCode ?? HttpStatus.ok,
        httpHeaders: responseHeaders,
      );
      await _startForegroundNotification();
      await _loadAddresses();
    } on Object catch (error) {
      _message(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await _service.stop();
    } finally {
      if (Platform.isAndroid) {
        try {
          await _native.stopLocalServerForeground();
        } on Object {
          // The Dart listener is already stopped; notification cleanup is best effort.
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startForegroundNotification() async {
    if (!Platform.isAndroid) return;
    try {
      final mode = _selectedMode == LocalTestServerMode.http
          ? 'HTTP'
          : 'TCP Echo';
      await _native.startLocalServerForeground(
        '$mode 服务正在监听',
        '端口 ${_service.snapshot.port} · 点击返回并停止服务',
      );
    } on Object catch (error) {
      _message('服务已启动，但前台通知不可用：${_friendlyError(error)}');
    }
  }

  Future<void> _loadAddresses() async {
    if (_loadingAddresses) return;
    if (mounted) setState(() => _loadingAddresses = true);
    final values = <String>{};
    try {
      final context = await _native.getNetworkContext();
      for (final address in [...context.lanAddresses, ...context.addresses]) {
        if (address.family == 'IPv4' &&
            address.address != '127.0.0.1' &&
            address.address != '0.0.0.0') {
          values.add(address.address);
        }
      }
    } on Object {
      // NetworkInterface is a portable fallback for tests and non-Android hosts.
    }
    try {
      values.addAll(await _service.discoverLocalIpv4Addresses());
    } on Object {
      // An empty list is an honest disconnected state.
    }
    if (!mounted) return;
    setState(() {
      _addresses = values.toList();
      _loadingAddresses = false;
    });
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _message('已复制：$value');
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: LocalizedText(value)));
  }

  String _friendlyError(Object error) {
    final value = error.toString();
    if (value.contains('errno = 98') ||
        value.contains('Address already in use')) {
      return '端口已被占用，请更换监听端口';
    }
    if (value.contains('Permission denied')) {
      return '系统拒绝监听该端口，请尝试 1024 以上端口';
    }
    return value.replaceFirst(RegExp(r'^(Exception|SocketException):\s*'), '');
  }

  String _formatBytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Map<String, Object?> _draftValue() => {
    'mode': _selectedMode.name,
    'port': _port.text,
    'response': _response.text,
    'contentType': _contentType.text,
    'statusCode': _statusCode.text,
    // Response headers can contain Set-Cookie/API keys during proxy tests.
    // Keep those values memory-only just like request credentials elsewhere.
    'responseHeaders': _safeDraftHeaders(_responseHeaders.text),
  };

  String _safeDraftHeaders(String value) {
    final sensitive = RegExp(
      r'(authorization|proxy-authorization|cookie|token|secret|api[-_]?key)',
      caseSensitive: false,
    );
    return value
        .split('\n')
        .where((line) {
          final separator = line.indexOf(':');
          if (separator <= 0) return true;
          return !sensitive.hasMatch(line.substring(0, separator).trim());
        })
        .join('\n');
  }

  Future<void> _restoreDraftAndLoadAddresses() async {
    final draft = await _drafts.load('tool.local_server');
    if (!mounted) return;
    if (draft != null && !_snapshot.running) {
      _selectedMode = LocalTestServerMode.values.firstWhere(
        (value) => value.name == draft.payload['mode'],
        orElse: () => _selectedMode,
      );
      _port.text = draft.payload['port']?.toString() ?? _port.text;
      _response.text = draft.payload['response']?.toString() ?? _response.text;
      _contentType.text =
          draft.payload['contentType']?.toString() ?? _contentType.text;
      _statusCode.text =
          draft.payload['statusCode']?.toString() ?? _statusCode.text;
      _responseHeaders.text =
          draft.payload['responseHeaders']?.toString() ?? '';
    }
    _draftLoaded = true;
    if (mounted) setState(() {});
    await _loadAddresses();
  }

  void _saveDraft() {
    if (_draftLoaded) {
      _drafts.scheduleSave('tool.local_server', _draftValue());
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LocalizedText(
        value,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          fontFamily: 'monospace',
        ),
      ),
      const SizedBox(height: 2),
      LocalizedText(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalizedText(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            LocalizedText(
              detail,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.detail,
    this.last = false,
  });

  final String number;
  final String title;
  final String detail;
  final bool last;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 30,
          child: Column(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: LocalizedText(
                  number,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                LocalizedText(
                  detail,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
