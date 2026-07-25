import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/native_network_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../services/wake_on_lan_service.dart';
import '../../../state/app_state.dart';

class WakeOnLanPage extends StatefulWidget {
  const WakeOnLanPage({super.key, required this.appState, this.initialMac});
  final AppState appState;
  final String? initialMac;

  @override
  State<WakeOnLanPage> createState() => _WakeOnLanPageState();
}

class _WakeOnLanPageState extends State<WakeOnLanPage> {
  late final _mac = TextEditingController(text: widget.initialMac ?? '');
  final _broadcast = TextEditingController(text: '255.255.255.255');
  final _port = TextEditingController(text: '9');
  final _repeat = TextEditingController(text: '3');
  final _secureOn = TextEditingController();
  bool _running = false;
  String? _message;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    for (final controller in [_mac, _broadcast, _port, _repeat]) {
      controller.addListener(_saveDraft);
    }
    unawaited(_restoreDraftAndSuggest());
  }

  @override
  void dispose() {
    if (_draftLoaded) unawaited(_drafts.save('tool.wol', _draftValue()));
    _drafts.dispose();
    _mac.dispose();
    _broadcast.dispose();
    _port.dispose();
    _repeat.dispose();
    _secureOn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('Wake-on-LAN')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        TextField(
          controller: _mac,
          enabled: !_running,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            label: LocalizedText('目标 MAC'),
            hintText: 'AA:BB:CC:DD:EE:FF',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _broadcast,
          enabled: !_running,
          decoration: const InputDecoration(
            label: LocalizedText('广播地址'),
            helper: LocalizedText('已根据当前 IPv4 子网自动建议，可手动修改'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _port,
                enabled: !_running,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  label: LocalizedText('UDP 端口'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _repeat,
                enabled: !_running,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(label: LocalizedText('发送次数')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _secureOn,
          enabled: !_running,
          obscureText: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            label: LocalizedText('SecureOn 密码（可选）'),
            hintText: '6 bytes / 12 hex',
            helper: LocalizedText('只在本次页面会话中使用，不写入普通草稿'),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _running ? null : _send,
          icon: const Icon(Icons.power_settings_new),
          label: const LocalizedText('发送魔术包'),
        ),
        if (_running) const LinearProgressIndicator(),
        if (_message != null) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LocalizedText(_message!),
            ),
          ),
        ],
        const SizedBox(height: 10),
        const LocalizedText(
          '设备必须支持并已启用 WOL，且广播包能到达目标二层网络。成功发送只代表数据报已交给系统，不代表设备一定开机。',
        ),
      ],
    ),
  );

  Future<void> _suggestBroadcast() async {
    try {
      final context = await NativeNetworkService().getNetworkContext();
      final ipv4 = context.lanAddresses
          .where((item) => item.family == 'IPv4')
          .firstOrNull;
      if (ipv4 == null) return;
      final octets = ipv4.address.split('.').map(int.parse).toList();
      if (octets.length != 4) return;
      final prefix = ipv4.prefixLength.clamp(0, 32);
      var value =
          (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
      final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
      value = (value & mask) | (~mask & 0xffffffff);
      if (!mounted) return;
      _broadcast.text =
          '${(value >> 24) & 255}.${(value >> 16) & 255}.${(value >> 8) & 255}.${value & 255}';
    } on Object {
      // Limited broadcast remains a valid fallback.
    }
  }

  Future<void> _send() async {
    setState(() {
      _running = true;
      _message = null;
    });
    try {
      final sent = await WakeOnLanService().send(
        mac: _mac.text,
        broadcast: _broadcast.text.trim(),
        port: int.tryParse(_port.text) ?? 9,
        repeat: int.tryParse(_repeat.text) ?? 3,
        secureOn: _secureOn.text,
      );
      if (mounted)
        setState(
          () => _message = '已向 ${_broadcast.text}:${_port.text} 发送 $sent 个魔术包',
        );
    } on Object catch (error) {
      if (mounted) setState(() => _message = '发送失败：$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Map<String, Object?> _draftValue() => {
    'mac': _mac.text,
    'broadcast': _broadcast.text,
    'port': _port.text,
    'repeat': _repeat.text,
    // SecureOn is a credential and deliberately remains memory-only.
  };

  Future<void> _restoreDraftAndSuggest() async {
    final draft = await _drafts.load('tool.wol');
    if (!mounted) return;
    if (draft != null) {
      _mac.text = draft.payload['mac']?.toString() ?? _mac.text;
      _broadcast.text =
          draft.payload['broadcast']?.toString() ?? _broadcast.text;
      _port.text = draft.payload['port']?.toString() ?? _port.text;
      _repeat.text = draft.payload['repeat']?.toString() ?? _repeat.text;
    } else {
      await _suggestBroadcast();
    }
    final initialMac = widget.initialMac?.trim();
    if (initialMac != null && initialMac.isNotEmpty) _mac.text = initialMac;
    _draftLoaded = true;
  }

  void _saveDraft() {
    if (_draftLoaded) _drafts.scheduleSave('tool.wol', _draftValue());
  }
}

extension _FirstOrNullWol<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
