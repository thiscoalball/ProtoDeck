import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../services/network_event_service.dart';

class NetworkEventMonitorPage extends StatefulWidget {
  const NetworkEventMonitorPage({super.key});

  @override
  State<NetworkEventMonitorPage> createState() =>
      _NetworkEventMonitorPageState();
}

class _NetworkEventMonitorPageState extends State<NetworkEventMonitorPage> {
  final _session = NetworkEventSession.instance;
  StreamSubscription<void>? _subscription;
  bool _paused = false;
  String _filter = '全部';

  List<NetworkEventRecord> get _events => _session.events;
  NetworkEventSnapshot? get _current => _session.current;
  bool get _running => _session.running;
  String? get _error => _session.error?.toString();

  @override
  void initState() {
    super.initState();
    _subscription = _session.changes.listen((_) {
      if (mounted && !_paused) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _events.reversed
        .where(
          (row) => _filter == '全部' || row.change.category.contains(_filter),
        )
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('网络事件监视器')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            _currentCard(),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: LocalizedText(error),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: LocalizedText(
                    '事件时间线 · ${_events.length}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _events.isEmpty ? null : _session.clear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const LocalizedText('清空'),
                ),
              ],
            ),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: const [
                  '全部',
                  '默认路由',
                  'Wi-Fi',
                  'DNS',
                  '网关',
                  '地址',
                  '互联网',
                ].length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final value = const [
                    '全部',
                    '默认路由',
                    'Wi-Fi',
                    'DNS',
                    '网关',
                    '地址',
                    '互联网',
                  ][index];
                  return ChoiceChip(
                    label: LocalizedText(value),
                    selected: _filter == value,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = value),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            if (visible.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Center(
                    child: LocalizedText(
                      _running ? '等待默认路由、DNS、地址或 Wi-Fi 变化' : '启动后记录当前会话的网络变化',
                    ),
                  ),
                ),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final row in visible.take(1000))
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: Icon(
                            _icon(row.change.category),
                            size: 19,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: LocalizedText(
                          row.change.category,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: LocalizedText(
                          '${row.change.before}  →  ${row.change.after}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: LocalizedText(
                          DateFormat('HH:mm:ss').format(row.snapshot.timestamp),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _currentCard() {
    final current = _current;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.timeline_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        current == null
                            ? '尚未开始观测'
                            : current.connected
                            ? '默认网络已连接'
                            : '没有默认网络',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      LocalizedText(
                        current == null
                            ? '记录路由、VPN、BSSID、DNS、网关和地址变化'
                            : '${current.transports.join(' + ')}${current.interfaceName == null ? '' : ' · ${current.interfaceName}'}',
                      ),
                    ],
                  ),
                ),
                if (_running)
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: Color(0xFF20B785),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            if (current != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(
                      current.validated
                          ? Icons.check_circle
                          : Icons.help_outline,
                      size: 17,
                    ),
                    label: LocalizedText(
                      current.validated ? '互联网已验证' : '互联网未验证',
                    ),
                  ),
                  if (current.bssid != null)
                    Chip(label: LocalizedText('BSSID ${current.bssid}')),
                  if (current.dnsServers.isNotEmpty)
                    Chip(
                      label: LocalizedText('DNS ${current.dnsServers.first}'),
                    ),
                  if (current.defaultGateways.isNotEmpty)
                    Chip(
                      label: LocalizedText(
                        '网关 ${current.defaultGateways.first}',
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (!_running)
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const LocalizedText('开始监视'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _paused = !_paused),
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                      label: LocalizedText(_paused ? '继续显示' : '暂停显示'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop_rounded),
                      label: const LocalizedText('停止监视'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _start() {
    setState(() {
      _paused = false;
    });
    _session.start();
  }

  Future<void> _stop() async {
    await _session.stop();
    if (mounted)
      setState(() {
        _paused = false;
      });
  }
}

IconData _icon(String category) {
  if (category.contains('Wi-Fi')) return Icons.wifi_rounded;
  if (category.contains('DNS')) return Icons.dns_outlined;
  if (category.contains('路由') || category.contains('网关'))
    return Icons.alt_route_rounded;
  if (category.contains('地址')) return Icons.pin_drop_outlined;
  if (category.contains('互联网')) return Icons.public_rounded;
  return Icons.swap_horiz_rounded;
}
