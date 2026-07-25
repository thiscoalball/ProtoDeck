import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/api_rule_engine.dart';
import '../../../services/api_workspace_store.dart';
import '../../../services/api_workbench_service.dart';
import '../../../services/socket_debug_service.dart';
import 'api_editor_widgets.dart';

class ApiRealtimeWorkbench extends StatefulWidget {
  const ApiRealtimeWorkbench({super.key, required this.protocol});

  /// 1 = WebSocket, 2 = SSE, 3 = MQTT.
  final int protocol;

  @override
  State<ApiRealtimeWorkbench> createState() => _ApiRealtimeWorkbenchState();
}

class _ApiRealtimeWorkbenchState extends State<ApiRealtimeWorkbench> {
  final _webSocket = WebSocketDebugSession();
  final _sse = SseDebugSession();
  final _mqtt = MqttDebugSession();
  final _workspaceStore = ApiWorkspaceStore();
  final _url = TextEditingController(text: 'wss://echo.websocket.events');
  final _message = TextEditingController(
    text: '{\n  "type": "ping",\n  "time": "{{timestamp}}"\n}',
  );
  final _sseExtract = TextEditingController(text: 'auto');
  final _sseBody = TextEditingController();
  final _mqttHost = TextEditingController(text: 'broker.emqx.io');
  final _mqttPort = TextEditingController(text: '1883');
  final _mqttClientId = TextEditingController(
    text: 'protodeck-${DateTime.now().millisecondsSinceEpoch}',
  );
  final _mqttUsername = TextEditingController();
  final _mqttPassword = TextEditingController();
  final _publishTopic = TextEditingController(text: 'protodeck/debug');
  final _query = <ApiFieldRow>[];
  final _headers = <ApiFieldRow>[];
  final _cookies = <ApiFieldRow>[];
  final _wsSubscriptions = <_WsSubscription>[];
  final _mqttSubscriptions = <_MqttSubscription>[];
  final _messages = <RealtimeMessage>[];
  final _connectionTemplates = <Map<String, Object?>>[];
  final _messageTemplates = <Map<String, Object?>>[];
  final _sentHistory = <Map<String, Object?>>[];
  final _subscriptions = <StreamSubscription<RealtimeMessage>>[];
  Timer? _draftTimer;
  bool _stateLoaded = false;
  String? _lastDraftFingerprint;
  String? _activeTemplateId;
  bool _connected = false;
  bool _busy = false;
  bool _mqttTls = false;
  bool _mqttCleanSession = true;
  bool _retain = false;
  int _mqttQos = 0;
  String _format = 'json';
  String? _selectedTopic;
  int _configTab = 0;
  int _sseView = 0;
  String _sseMethod = 'GET';
  String _mergedSseText = '';

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _webSocket.messages.listen(_onMessage),
      _sse.messages.listen(_onMessage),
      _mqtt.messages.listen(_onMessage),
    ]);
    _applyProtocolDefaults();
    _loadState();
    _draftTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _saveDraftIfChanged(),
    );
  }

  @override
  void didUpdateWidget(covariant ApiRealtimeWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.protocol != widget.protocol) {
      _disconnect();
      setState(() {
        _messages.clear();
        _connected = false;
        _configTab = 0;
        _applyProtocolDefaults();
      });
    }
  }

  void _applyProtocolDefaults() {
    if (widget.protocol == 1 && !_url.text.startsWith('ws')) {
      _url.text = 'wss://echo.websocket.events';
    }
    if (widget.protocol == 2 && _url.text.startsWith('ws')) {
      _url.text = 'https://example.com/events';
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (_stateLoaded) unawaited(_saveDraft(force: true));
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _webSocket.dispose();
    _sse.dispose();
    _mqtt.dispose();
    for (final controller in [
      _url,
      _message,
      _sseExtract,
      _sseBody,
      _mqttHost,
      _mqttPort,
      _mqttClientId,
      _mqttUsername,
      _mqttPassword,
      _publishTopic,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: LocalizedText(
              switch (widget.protocol) {
                1 => 'WebSocket 调试',
                2 => 'SSE 流调试',
                _ => 'MQTT 调试',
              },
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton.filledTonal(
            onPressed: _saveConnectionTemplate,
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: context.tr('保存连接配置'),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            onPressed: _showConnectionTemplates,
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: context.tr('连接配置模板'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (widget.protocol == 3) _mqttConnection() else _httpConnection(),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy ? null : (_connected ? _disconnect : _connect),
          icon: Icon(_connected ? Icons.link_off : Icons.link),
          label: LocalizedText(_busy ? '处理中…' : (_connected ? '断开连接' : '建立连接')),
        ),
      ),
      const SizedBox(height: 14),
      if (widget.protocol == 1) _webSocketWorkspace(),
      if (widget.protocol == 2) _sseWorkspace(),
      if (widget.protocol == 3) _mqttWorkspace(),
    ],
  );

  Widget _httpConnection() => Column(
    children: [
      Row(
        children: [
          if (widget.protocol == 2) ...[
            SizedBox(
              width: 142,
              child: DropdownButtonFormField<String>(
                key: ValueKey('sse-method-$_sseMethod'),
                isExpanded: true,
                initialValue: _sseMethod,
                items: const ['GET', 'POST']
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: LocalizedText(value),
                      ),
                    )
                    .toList(),
                onChanged: _connected
                    ? null
                    : (value) => setState(() => _sseMethod = value ?? 'GET'),
                decoration: const InputDecoration(labelText: 'Method'),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              enabled: !_connected,
              decoration: InputDecoration(
                labelText: widget.protocol == 1
                    ? 'ws:// / wss:// URL'
                    : 'SSE URL',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: 0,
              label: LocalizedText('Params ${_query.length}'),
            ),
            ButtonSegment(
              value: 1,
              label: LocalizedText('Headers ${_headers.length}'),
            ),
            ButtonSegment(
              value: 2,
              label: LocalizedText('Cookies ${_cookies.length}'),
            ),
          ],
          selected: {_configTab},
          onSelectionChanged: _connected
              ? null
              : (value) => setState(() => _configTab = value.first),
        ),
      ),
      const SizedBox(height: 8),
      ApiKeyValueEditor(
        rows: switch (_configTab) {
          0 => _query,
          1 => _headers,
          _ => _cookies,
        },
        onChanged: () => setState(() {}),
        nameHint: switch (_configTab) {
          0 => 'Query 参数',
          1 => 'Header 名称',
          _ => 'Cookie 名称',
        },
        valueHint: '值',
      ),
      if (widget.protocol == 2 && _sseMethod == 'POST')
        TextField(
          controller: _sseBody,
          enabled: !_connected,
          minLines: 4,
          maxLines: 12,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(
            label: LocalizedText('SSE 请求 Body'),
            hintText: '{"stream":true}',
          ),
        ),
    ],
  );

  Widget _mqttConnection() => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _mqttHost,
                  enabled: !_connected,
                  decoration: const InputDecoration(labelText: 'Broker Host'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _mqttPort,
                  enabled: !_connected,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(label: LocalizedText('端口')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _mqttClientId,
            enabled: !_connected,
            decoration: const InputDecoration(labelText: 'Client ID'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _mqttUsername,
                  enabled: !_connected,
                  decoration: const InputDecoration(
                    label: LocalizedText('用户名（可选）'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _mqttPassword,
                  enabled: !_connected,
                  obscureText: true,
                  decoration: const InputDecoration(
                    label: LocalizedText('密码（可选）'),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _mqttTls,
                  onChanged: _connected
                      ? null
                      : (value) => setState(() {
                          _mqttTls = value;
                          if (value && _mqttPort.text == '1883')
                            _mqttPort.text = '8883';
                        }),
                  title: const LocalizedText('TLS'),
                ),
              ),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _mqttCleanSession,
                  onChanged: _connected
                      ? null
                      : (value) => setState(() => _mqttCleanSession = value),
                  title: const LocalizedText('Clean Session'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _webSocketWorkspace() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _composer(title: '发送消息', onSend: _sendWebSocket),
      const SizedBox(height: 14),
      Row(
        children: [
          LocalizedText(
            '订阅消息模板',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: _addWsSubscription,
            icon: const Icon(Icons.add),
            label: const LocalizedText('添加'),
          ),
        ],
      ),
      LocalizedText(
        '原生 WebSocket 没有统一的订阅帧；这里保存服务端要求的订阅 JSON/文本，连接后可逐条发送。',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 7),
      for (final item in _wsSubscriptions)
        Card(
          margin: const EdgeInsets.only(bottom: 7),
          child: ListTile(
            title: LocalizedText(item.name),
            subtitle: LocalizedText(
              item.payload,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  onPressed: _connected
                      ? () => _webSocket.send(item.payload)
                      : null,
                  icon: const Icon(Icons.send),
                  tooltip: context.tr('发送订阅帧'),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _wsSubscriptions.remove(item)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
      _messageTimeline(title: 'Messages'),
    ],
  );

  Widget _sseWorkspace() {
    final events = _messages
        .where(
          (message) => message.protocol == 'SSE' && message.direction == 'RX',
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _sseExtract,
          decoration: const InputDecoration(
            label: LocalizedText('内容合并规则'),
            hint: LocalizedText('auto 或 choices[0].delta.content'),
            helper: LocalizedText(
              'auto 会识别 OpenAI/Claude 以及 content、text、message 字段',
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: 0,
                label: LocalizedText('事件时间线 ${events.length}'),
              ),
              const ButtonSegment(value: 1, label: LocalizedText('JSON 数组')),
              const ButtonSegment(value: 2, label: LocalizedText('合并内容')),
            ],
            selected: {_sseView},
            onSelectionChanged: (value) =>
                setState(() => _sseView = value.first),
          ),
        ),
        const SizedBox(height: 8),
        if (_sseView == 0)
          _messageTimeline(title: '')
        else
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 180, maxHeight: 520),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _sseView == 1
                    ? _sseAsJson(events)
                    : (_mergedSseText.isEmpty
                          ? context.tr('等待可合并的数据片段…')
                          : _mergedSseText),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _mqttWorkspace() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          LocalizedText('订阅列表', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: _addMqttSubscription,
            icon: const Icon(Icons.add),
            label: const LocalizedText('添加订阅'),
          ),
        ],
      ),
      if (_mqttSubscriptions.isEmpty)
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.rss_feed_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                const LocalizedText(
                  '还没有订阅 Topic',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                LocalizedText(
                  '例如 sensors/+/temperature 或 devices/#',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _addMqttSubscription,
                  icon: const Icon(Icons.add_rounded),
                  label: const LocalizedText('创建第一条订阅'),
                ),
              ],
            ),
          ),
        )
      else
        ..._mqttSubscriptions.map(
          (item) => Card(
            margin: const EdgeInsets.only(bottom: 7),
            child: ListTile(
              leading: Switch(
                value: item.active,
                onChanged: _connected
                    ? (value) => _toggleMqttSubscription(item, value)
                    : null,
              ),
              title: LocalizedText(
                item.topic,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              subtitle: LocalizedText(
                'QoS ${item.qos} · 已接收 ${item.received} 条',
              ),
              trailing: IconButton(
                onPressed: () {
                  if (item.active && _connected) _mqtt.unsubscribe(item.topic);
                  setState(() => _mqttSubscriptions.remove(item));
                },
                icon: const Icon(Icons.delete_outline),
                tooltip: context.tr('删除订阅'),
              ),
              onTap: () => setState(
                () => _selectedTopic = _selectedTopic == item.topic
                    ? null
                    : item.topic,
              ),
              selected: _selectedTopic == item.topic,
            ),
          ),
        ),
      const SizedBox(height: 10),
      TextField(
        controller: _publishTopic,
        decoration: const InputDecoration(label: LocalizedText('发布 Topic')),
      ),
      const SizedBox(height: 8),
      _composer(title: '发布消息', onSend: _publishMqtt, mqtt: true),
      const SizedBox(height: 12),
      _messageTimeline(
        title: _selectedTopic == null
            ? '全部 MQTT 消息'
            : 'Topic · $_selectedTopic',
      ),
    ],
  );

  Widget _menuShell({required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );

  Widget _composer({
    required String title,
    required VoidCallback onSend,
    bool mqtt = false,
  }) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: LocalizedText(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              _menuShell(
                child: DropdownButton<String>(
                  value: _format,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(14),
                  items: const [
                    DropdownMenuItem(
                      value: 'text',
                      child: LocalizedText('Text'),
                    ),
                    DropdownMenuItem(
                      value: 'json',
                      child: LocalizedText('JSON'),
                    ),
                    DropdownMenuItem(value: 'hex', child: LocalizedText('Hex')),
                    DropdownMenuItem(
                      value: 'base64',
                      child: LocalizedText('Base64'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _format = value ?? 'text'),
                ),
              ),
            ],
          ),
          if (mqtt) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _menuShell(
                  child: DropdownButton<int>(
                    value: _mqttQos,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(14),
                    items: const [
                      DropdownMenuItem(value: 0, child: LocalizedText('QoS 0')),
                      DropdownMenuItem(value: 1, child: LocalizedText('QoS 1')),
                    ],
                    onChanged: (value) => setState(() => _mqttQos = value ?? 0),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.bookmark_outline_rounded, size: 16),
                  label: const LocalizedText('Retain'),
                  selected: _retain,
                  onSelected: (value) => setState(() => _retain = value),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _message,
            minLines: 5,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: _format == 'hex'
                  ? '48 65 6C 6C 6F'
                  : context.tr('消息内容'),
              suffixIcon: _format == 'json'
                  ? IconButton(
                      onPressed: _formatMessage,
                      icon: const Icon(Icons.auto_fix_high),
                      tooltip: context.tr('格式化 JSON'),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _connected ? onSend : null,
                  icon: const Icon(Icons.send),
                  label: LocalizedText(mqtt ? '发布' : '发送消息'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _saveMessageTemplate,
                icon: const Icon(Icons.bookmark_add_outlined),
                tooltip: context.tr('保存消息模板'),
              ),
            ],
          ),
          if (_messageTemplates.isNotEmpty || _sentHistory.isNotEmpty) ...[
            const SizedBox(height: 8),
            _savedMessagesPanel(onSend: onSend, mqtt: mqtt),
          ],
        ],
      ),
    ),
  );

  Widget _savedMessagesPanel({
    required VoidCallback onSend,
    required bool mqtt,
  }) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: EdgeInsets.zero,
    title: const LocalizedText('消息模板与发送历史'),
    subtitle: LocalizedText(
      '${_messageTemplates.length} 个模板 · ${_sentHistory.length} 条历史',
    ),
    children: [
      if (_messageTemplates.isNotEmpty) ...[
        const Align(
          alignment: Alignment.centerLeft,
          child: LocalizedText(
            '消息模板',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        for (var index = 0; index < _messageTemplates.length; index++)
          _savedMessageTile(
            _messageTemplates[index],
            templateIndex: index,
            onSend: onSend,
          ),
      ],
      if (_sentHistory.isNotEmpty) ...[
        Row(
          children: [
            const Expanded(
              child: LocalizedText(
                '最近发送',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: _clearSentHistory,
              child: const LocalizedText('清空历史'),
            ),
          ],
        ),
        for (var index = 0; index < _sentHistory.length.clamp(0, 12); index++)
          _savedMessageTile(_sentHistory[index], onSend: onSend),
      ],
    ],
  );

  Widget _savedMessageTile(
    Map<String, Object?> value, {
    required VoidCallback onSend,
    int? templateIndex,
  }) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      templateIndex == null ? Icons.history_rounded : Icons.bookmark_outline,
    ),
    title: LocalizedText(
      value['name']?.toString() ?? value['payload']?.toString() ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: LocalizedText(
      [
        value['format']?.toString() ?? 'text',
        if (value['topic']?.toString().isNotEmpty == true)
          value['topic'].toString(),
        value['payload']?.toString() ?? '',
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
    ),
    onTap: () => _applySavedMessage(value),
    trailing: Wrap(
      spacing: 0,
      children: [
        IconButton(
          onPressed: _connected
              ? () {
                  _applySavedMessage(value);
                  onSend();
                }
              : null,
          icon: const Icon(Icons.replay_rounded, size: 19),
          tooltip: context.tr('再次发送'),
        ),
        if (templateIndex != null)
          IconButton(
            onPressed: () => _deleteMessageTemplate(templateIndex),
            icon: const Icon(Icons.delete_outline, size: 19),
            tooltip: context.tr('删除消息模板'),
          ),
      ],
    ),
  );

  Widget _messageTimeline({required String title}) {
    final visible = _messages.where((message) {
      if (widget.protocol == 1) return message.protocol == 'WebSocket';
      if (widget.protocol == 2) return message.protocol == 'SSE';
      return message.protocol == 'MQTT' &&
          (_selectedTopic == null ||
              message.channel == _selectedTopic ||
              message.direction == 'SYS');
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Row(
            children: [
              LocalizedText(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: visible.isEmpty
                    ? null
                    : () => setState(() {
                        _messages.removeWhere((m) => visible.contains(m));
                        _mergedSseText = '';
                      }),
                child: const LocalizedText('清空'),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        if (visible.isEmpty)
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: LocalizedText('连接、发送或收到的消息会显示在这里')),
            ),
          )
        else
          ...visible
              .take(300)
              .map(
                (message) => RealtimeMessageCard(
                  message: message,
                  onTap: () => showRealtimeMessageDetails(context, message),
                ),
              ),
      ],
    );
  }

  String _connectionUrl() {
    var uri = Uri.parse(_url.text.trim());
    final values = <String, List<String>>{
      for (final entry in uri.queryParametersAll.entries)
        entry.key: [...entry.value],
    };
    for (final entry in enabledFieldMap(_query).entries) {
      values.putIfAbsent(entry.key, () => []).add(entry.value);
    }
    return uri
        .replace(queryParameters: values.isEmpty ? null : values)
        .toString();
  }

  Map<String, String> _handshakeHeaders() {
    final values = enabledFieldMap(_headers);
    final cookie = enabledFieldMap(
      _cookies,
    ).entries.map((e) => '${e.key}=${e.value}').join('; ');
    if (cookie.isNotEmpty) values['Cookie'] = cookie;
    return values;
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      if (widget.protocol == 1)
        await _webSocket.connect(
          _connectionUrl(),
          headers: _handshakeHeaders(),
        );
      if (widget.protocol == 2)
        await _sse.connect(
          _connectionUrl(),
          headers: _handshakeHeaders(),
          method: _sseMethod,
          body: _sseBody.text,
        );
      if (widget.protocol == 3) {
        await _mqtt.connect(
          host: _mqttHost.text.trim(),
          port: int.tryParse(_mqttPort.text) ?? (_mqttTls ? 8883 : 1883),
          clientId: _mqttClientId.text.trim(),
          username: _mqttUsername.text,
          password: _mqttPassword.text,
          tls: _mqttTls,
          cleanSession: _mqttCleanSession,
        );
      }
      if (mounted) setState(() => _connected = true);
    } on Object catch (error) {
      _show('连接失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (widget.protocol == 1) await _webSocket.disconnect();
    if (widget.protocol == 2) await _sse.disconnect();
    if (widget.protocol == 3) await _mqtt.disconnect();
    if (mounted)
      setState(() {
        _connected = false;
        for (final item in _mqttSubscriptions) {
          item.active = false;
        }
      });
  }

  Uint8List _messageBytes() {
    final source = _message.text
        .replaceAll('{{timestamp}}', '${DateTime.now().millisecondsSinceEpoch}')
        .replaceAll('{{iso_time}}', DateTime.now().toIso8601String());
    if (_format == 'json') {
      final value = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(source));
      return Uint8List.fromList(utf8.encode(value));
    }
    if (_format == 'hex')
      return SocketDebugService.parsePayload(source, hex: true);
    if (_format == 'base64')
      return base64.decode(base64.normalize(source.trim()));
    return Uint8List.fromList(utf8.encode(source));
  }

  void _sendWebSocket() {
    try {
      final bytes = _messageBytes();
      if (_format == 'hex' || _format == 'base64')
        _webSocket.sendBinary(bytes);
      else
        _webSocket.send(utf8.decode(bytes));
    } on Object catch (error) {
      _show('$error');
    }
  }

  void _publishMqtt() {
    try {
      _mqtt.publish(
        _publishTopic.text.trim(),
        _messageBytes(),
        qos: _mqttQos,
        retain: _retain,
      );
    } on Object catch (error) {
      _show('$error');
    }
  }

  void _formatMessage() {
    try {
      _message.text = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(_message.text));
    } on Object catch (error) {
      _show('$error');
    }
  }

  void _onMessage(RealtimeMessage message) {
    if (!mounted) return;
    var saveSentHistory = false;
    setState(() {
      _messages.insert(0, message);
      if (_messages.length > 600) _messages.removeLast();
      if (message.direction == 'TX') {
        _recordSentMessage(message);
        saveSentHistory = true;
      }
      if (message.protocol == 'SSE' && message.direction == 'RX')
        _mergedSseText += _extractSseContent(message.data);
      if (message.protocol == 'MQTT' &&
          message.direction == 'RX' &&
          message.channel != null) {
        for (final item in _mqttSubscriptions) {
          if (_mqttTopicMatches(item.topic, message.channel!)) item.received++;
        }
      }
    });
    if (saveSentHistory) unawaited(_persistSentHistory());
  }

  String _extractSseContent(String data) {
    try {
      final value = jsonDecode(data);
      final rule = _sseExtract.text.trim();
      if (rule.isNotEmpty && rule != 'auto') {
        final extracted = resolveJsonPath(value, rule);
        return extracted is String
            ? extracted
            : extracted == null
            ? ''
            : jsonEncode(extracted);
      }
      if (value is Map) {
        Object? candidate;
        final choices = value['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final delta = (choices.first as Map)['delta'];
          if (delta is Map) candidate = delta['content'];
          candidate ??= (choices.first as Map)['text'];
        }
        candidate ??= value['content'] ?? value['text'] ?? value['message'];
        if (candidate is String) return candidate;
        if (candidate is Map && candidate['content'] is String)
          return candidate['content'] as String;
      }
    } on Object {
      return data;
    }
    return '';
  }

  String _sseAsJson(List<RealtimeMessage> events) =>
      const JsonEncoder.withIndent('  ').convert([
        for (final event in events.reversed)
          {
            'time': event.time.toIso8601String(),
            'event': event.channel,
            'id': event.metadata['id'],
            'data': _decodeJson(event.data),
          },
      ]);

  Object? _decodeJson(String value) {
    try {
      return jsonDecode(value);
    } on Object {
      return value;
    }
  }

  Future<void> _addWsSubscription() async {
    final name = TextEditingController(text: context.tr('订阅'));
    final payload = TextEditingController(
      text: '{"action":"subscribe","channel":"updates"}',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('添加订阅消息模板'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(label: LocalizedText('名称')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: payload,
              minLines: 4,
              maxLines: 10,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                label: LocalizedText('发送到服务端的订阅帧'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('添加'),
          ),
        ],
      ),
    );
    if (accepted == true)
      setState(
        () => _wsSubscriptions.add(_WsSubscription(name.text, payload.text)),
      );
    name.dispose();
    payload.dispose();
  }

  Future<void> _addMqttSubscription() async {
    final topic = TextEditingController(text: 'protodeck/#');
    var qos = 0;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const LocalizedText('添加 MQTT 订阅'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: topic,
                decoration: const InputDecoration(labelText: 'Topic Filter'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: LocalizedText('QoS 0')),
                  ButtonSegment(value: 1, label: LocalizedText('QoS 1')),
                ],
                selected: {qos},
                onSelectionChanged: (value) =>
                    setDialogState(() => qos = value.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LocalizedText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedText('添加'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && topic.text.trim().isNotEmpty)
      setState(
        () => _mqttSubscriptions.add(_MqttSubscription(topic.text.trim(), qos)),
      );
    topic.dispose();
  }

  void _toggleMqttSubscription(_MqttSubscription item, bool active) {
    try {
      if (active)
        _mqtt.subscribe(item.topic, qos: item.qos);
      else
        _mqtt.unsubscribe(item.topic);
      setState(() => item.active = active);
    } on Object catch (error) {
      _show('$error');
    }
  }

  String get _workspaceId => switch (widget.protocol) {
    1 => 'websocket',
    2 => 'sse',
    _ => 'mqtt',
  };

  Map<String, Object?> _snapshot() => {
    'url': _url.text,
    'query': _query.map((row) => row.toJson()).toList(),
    'headers': _headers.map((row) => row.toJson()).toList(),
    'cookies': _cookies.map((row) => row.toJson()).toList(),
    'message': _message.text,
    'format': _format,
    'configTab': _configTab,
    'wsSubscriptions': [
      for (final item in _wsSubscriptions)
        {'name': item.name, 'payload': item.payload},
    ],
    'sseMethod': _sseMethod,
    'sseExtract': _sseExtract.text,
    'sseBody': _sseBody.text,
    'mqttHost': _mqttHost.text,
    'mqttPort': _mqttPort.text,
    'mqttClientId': _mqttClientId.text,
    'mqttUsername': _mqttUsername.text,
    'mqttTls': _mqttTls,
    'mqttCleanSession': _mqttCleanSession,
    'publishTopic': _publishTopic.text,
    'mqttQos': _mqttQos,
    'retain': _retain,
    'mqttSubscriptions': [
      for (final item in _mqttSubscriptions)
        {'topic': item.topic, 'qos': item.qos},
    ],
  };

  Map<String, String> _secretSnapshot() => {
    if (widget.protocol == 3) 'mqttPassword': _mqttPassword.text,
  };

  void _applyState(
    Map<String, Object?> value, {
    Map<String, String> secrets = const {},
  }) {
    List<ApiFieldRow> rows(String key) =>
        (value[key] as List<Object?>? ?? const [])
            .whereType<Map>()
            .map(
              (item) => ApiFieldRow.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList();
    _url.text = value['url']?.toString() ?? _url.text;
    _replaceRows(_query, rows('query'));
    _replaceRows(_headers, rows('headers'));
    _replaceRows(_cookies, rows('cookies'));
    _message.text = value['message']?.toString() ?? _message.text;
    _format = value['format']?.toString() ?? 'json';
    _configTab = (value['configTab'] as num?)?.toInt().clamp(0, 2) ?? 0;
    _wsSubscriptions
      ..clear()
      ..addAll(
        (value['wsSubscriptions'] as List<Object?>? ?? const [])
            .whereType<Map>()
            .map(
              (item) => _WsSubscription(
                item['name']?.toString() ?? '订阅',
                item['payload']?.toString() ?? '',
              ),
            ),
      );
    _sseMethod = value['sseMethod']?.toString() ?? 'GET';
    _sseExtract.text = value['sseExtract']?.toString() ?? 'auto';
    _sseBody.text = value['sseBody']?.toString() ?? '';
    _mqttHost.text = value['mqttHost']?.toString() ?? _mqttHost.text;
    _mqttPort.text = value['mqttPort']?.toString() ?? _mqttPort.text;
    _mqttClientId.text =
        value['mqttClientId']?.toString() ?? _mqttClientId.text;
    _mqttUsername.text = value['mqttUsername']?.toString() ?? '';
    _mqttPassword.text = secrets['mqttPassword'] ?? '';
    _mqttTls = value['mqttTls'] == true;
    _mqttCleanSession = value['mqttCleanSession'] != false;
    _publishTopic.text =
        value['publishTopic']?.toString() ?? _publishTopic.text;
    _mqttQos = (value['mqttQos'] as num?)?.toInt().clamp(0, 1) ?? 0;
    _retain = value['retain'] == true;
    _mqttSubscriptions
      ..clear()
      ..addAll(
        (value['mqttSubscriptions'] as List<Object?>? ?? const [])
            .whereType<Map>()
            .map(
              (item) => _MqttSubscription(
                item['topic']?.toString() ?? '',
                (item['qos'] as num?)?.toInt().clamp(0, 1) ?? 0,
              ),
            )
            .where((item) => item.topic.isNotEmpty),
      );
  }

  void _replaceRows(List<ApiFieldRow> target, List<ApiFieldRow> source) {
    target
      ..clear()
      ..addAll(source);
  }

  Future<void> _loadState() async {
    final workspace = _workspaceId;
    final values = await Future.wait<Object?>([
      _workspaceStore.loadMap(ApiWorkspaceStore.draftKey(workspace)),
      _workspaceStore.loadList(ApiWorkspaceStore.templatesKey(workspace)),
      _workspaceStore.loadList(
        ApiWorkspaceStore.messageTemplatesKey(workspace),
      ),
      _workspaceStore.loadList(ApiWorkspaceStore.sentHistoryKey(workspace)),
      _workspaceStore.loadSecrets('${workspace}_draft'),
    ]);
    if (!mounted || workspace != _workspaceId) return;
    setState(() {
      final draft = values[0] as Map<String, Object?>?;
      _connectionTemplates
        ..clear()
        ..addAll(values[1] as List<Map<String, Object?>>);
      _messageTemplates
        ..clear()
        ..addAll(values[2] as List<Map<String, Object?>>);
      _sentHistory
        ..clear()
        ..addAll(values[3] as List<Map<String, Object?>>);
      if (draft != null) {
        _applyState(draft, secrets: values[4] as Map<String, String>);
      }
      _stateLoaded = true;
      _lastDraftFingerprint = jsonEncode(_snapshot());
    });
  }

  Future<void> _saveDraftIfChanged() async {
    if (!_stateLoaded) return;
    final fingerprint = jsonEncode(_snapshot());
    if (fingerprint == _lastDraftFingerprint) return;
    await _saveDraft(fingerprint: fingerprint);
  }

  Future<void> _saveDraft({String? fingerprint, bool force = false}) async {
    if (!_stateLoaded && !force) return;
    final workspace = _workspaceId;
    final value = _snapshot();
    final nextFingerprint = fingerprint ?? jsonEncode(value);
    if (!force && nextFingerprint == _lastDraftFingerprint) return;
    await Future.wait([
      _workspaceStore.saveMap(ApiWorkspaceStore.draftKey(workspace), value),
      _workspaceStore.saveSecrets('${workspace}_draft', _secretSnapshot()),
    ]);
    _lastDraftFingerprint = nextFingerprint;
  }

  Future<void> _saveConnectionTemplate({
    Map<String, Object?>? overwrite,
  }) async {
    final name = TextEditingController(
      text:
          overwrite?['name']?.toString() ??
          switch (widget.protocol) {
            1 => 'WebSocket ${Uri.tryParse(_url.text)?.host ?? ''}',
            2 => 'SSE ${Uri.tryParse(_url.text)?.host ?? ''}',
            _ => 'MQTT ${_mqttHost.text}',
          },
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('保存连接配置'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(label: LocalizedText('配置名称')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('保存'),
          ),
        ],
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      final id =
          overwrite?['id']?.toString() ??
          '${_workspaceId}_${DateTime.now().microsecondsSinceEpoch}';
      final value = <String, Object?>{
        ..._snapshot(),
        'id': id,
        'name': name.text.trim(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      final index = _connectionTemplates.indexWhere(
        (item) => item['id']?.toString() == id,
      );
      setState(() {
        if (index < 0) {
          _connectionTemplates.insert(0, value);
        } else {
          _connectionTemplates[index] = value;
        }
        _activeTemplateId = id;
      });
      await Future.wait([
        _workspaceStore.saveList(
          ApiWorkspaceStore.templatesKey(_workspaceId),
          _connectionTemplates,
        ),
        _workspaceStore.saveSecrets(
          '${_workspaceId}_template_$id',
          _secretSnapshot(),
        ),
      ]);
      _show(index < 0 ? '连接配置已保存' : '连接配置已更新');
    }
    name.dispose();
  }

  Future<void> _loadConnectionTemplate(int index) async {
    if (index < 0 || index >= _connectionTemplates.length) return;
    final value = _connectionTemplates[index];
    final id = value['id']?.toString() ?? 'legacy_$index';
    final secrets = await _workspaceStore.loadSecrets(
      '${_workspaceId}_template_$id',
    );
    if (!mounted) return;
    setState(() {
      _applyState(value, secrets: secrets);
      _activeTemplateId = id;
    });
  }

  Future<void> _deleteConnectionTemplate(int index) async {
    if (index < 0 || index >= _connectionTemplates.length) return;
    final removed = _connectionTemplates.removeAt(index);
    final id = removed['id']?.toString();
    await _workspaceStore.saveList(
      ApiWorkspaceStore.templatesKey(_workspaceId),
      _connectionTemplates,
    );
    if (id != null) {
      await _workspaceStore.deleteSecrets('${_workspaceId}_template_$id');
    }
    if (mounted) setState(() {});
  }

  Future<void> _showConnectionTemplates() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .68,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: LocalizedText(
                        '连接配置模板',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _saveConnectionTemplate();
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const LocalizedText('保存当前配置'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _connectionTemplates.isEmpty
                    ? const Center(child: LocalizedText('暂无保存模板'))
                    : ListView.builder(
                        itemCount: _connectionTemplates.length,
                        itemBuilder: (context, index) {
                          final value = _connectionTemplates[index];
                          return ListTile(
                            selected:
                                value['id']?.toString() == _activeTemplateId,
                            leading: Icon(
                              widget.protocol == 3
                                  ? Icons.hub_outlined
                                  : Icons.cable_rounded,
                            ),
                            title: LocalizedText(
                              value['name']?.toString() ?? '连接配置',
                            ),
                            subtitle: LocalizedText(
                              widget.protocol == 3
                                  ? '${value['mqttHost'] ?? ''}:${value['mqttPort'] ?? ''}'
                                  : value['url']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _loadConnectionTemplate(index);
                            },
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) {
                                Navigator.pop(sheetContext);
                                if (action == 'overwrite') {
                                  _saveConnectionTemplate(overwrite: value);
                                } else {
                                  _deleteConnectionTemplate(index);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'overwrite',
                                  child: LocalizedText('用当前配置覆盖'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: LocalizedText('删除配置'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveMessageTemplate() async {
    final name = TextEditingController(
      text: context.tr('消息 ${_messageTemplates.length + 1}'),
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('保存消息模板'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(label: LocalizedText('模板名称')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('保存'),
          ),
        ],
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      setState(() {
        _messageTemplates.insert(0, {
          'id': 'message_${DateTime.now().microsecondsSinceEpoch}',
          'name': name.text.trim(),
          ..._currentMessageRecord(),
        });
      });
      await _workspaceStore.saveList(
        ApiWorkspaceStore.messageTemplatesKey(_workspaceId),
        _messageTemplates,
      );
    }
    name.dispose();
  }

  Map<String, Object?> _currentMessageRecord() => {
    'payload': _message.text,
    'format': _format,
    if (widget.protocol == 3) 'topic': _publishTopic.text,
    if (widget.protocol == 3) 'qos': _mqttQos,
    if (widget.protocol == 3) 'retain': _retain,
    'time': DateTime.now().toIso8601String(),
  };

  void _recordSentMessage(RealtimeMessage message) {
    final value = {
      ..._currentMessageRecord(),
      'payload': _format == 'hex' || _format == 'base64'
          ? _message.text
          : message.data,
    };
    _sentHistory.removeWhere(
      (item) =>
          item['payload'] == value['payload'] &&
          item['format'] == value['format'] &&
          item['topic'] == value['topic'],
    );
    _sentHistory.insert(0, value);
    if (_sentHistory.length > 50)
      _sentHistory.removeRange(50, _sentHistory.length);
  }

  Future<void> _persistSentHistory() => _workspaceStore.saveList(
    ApiWorkspaceStore.sentHistoryKey(_workspaceId),
    _sentHistory,
  );

  void _applySavedMessage(Map<String, Object?> value) {
    setState(() {
      _message.text = value['payload']?.toString() ?? '';
      _format = value['format']?.toString() ?? 'text';
      if (widget.protocol == 3) {
        _publishTopic.text = value['topic']?.toString() ?? _publishTopic.text;
        _mqttQos = (value['qos'] as num?)?.toInt().clamp(0, 1) ?? 0;
        _retain = value['retain'] == true;
      }
    });
  }

  Future<void> _deleteMessageTemplate(int index) async {
    if (index < 0 || index >= _messageTemplates.length) return;
    setState(() => _messageTemplates.removeAt(index));
    await _workspaceStore.saveList(
      ApiWorkspaceStore.messageTemplatesKey(_workspaceId),
      _messageTemplates,
    );
  }

  Future<void> _clearSentHistory() async {
    setState(_sentHistory.clear);
    await _persistSentHistory();
  }

  bool _mqttTopicMatches(String filter, String topic) {
    final f = filter.split('/');
    final t = topic.split('/');
    for (var i = 0; i < f.length; i++) {
      if (f[i] == '#') return true;
      if (i >= t.length || (f[i] != '+' && f[i] != t[i])) return false;
    }
    return f.length == t.length;
  }

  void _show(String text) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText(text)));
  }
}

class _WsSubscription {
  const _WsSubscription(this.name, this.payload);
  final String name;
  final String payload;
}

class _MqttSubscription {
  _MqttSubscription(this.topic, this.qos);
  final String topic;
  final int qos;
  bool active = false;
  int received = 0;
}
