import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/native_network_service.dart';
import '../../../services/wake_on_lan_service.dart';

class WakeOnLanPage extends StatefulWidget {
  const WakeOnLanPage({super.key, this.initialMac});
  final String? initialMac;

  @override
  State<WakeOnLanPage> createState() => _WakeOnLanPageState();
}

class _WakeOnLanPageState extends State<WakeOnLanPage> {
  late final _mac = TextEditingController(text: widget.initialMac ?? '');
  final _broadcast = TextEditingController(text: '255.255.255.255');
  final _port = TextEditingController(text: '9');
  final _repeat = TextEditingController(text: '3');
  bool _running = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _suggestBroadcast();
  }

  @override
  void dispose() {
    _mac.dispose();
    _broadcast.dispose();
    _port.dispose();
    _repeat.dispose();
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
}

extension _FirstOrNullWol<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
