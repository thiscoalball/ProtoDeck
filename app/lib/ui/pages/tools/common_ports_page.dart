import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../models/tool_route_args.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../tool_launcher.dart';

class CommonPortsPage extends StatefulWidget {
  const CommonPortsPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<CommonPortsPage> createState() => _CommonPortsPageState();
}

class _CommonPortsPageState extends State<CommonPortsPage> {
  final _search = TextEditingController();
  var _query = '';
  var _transport = 'ALL';
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  static const _ports = [
    (20, 'TCP', 'FTP Data', 'FTP 数据传输'),
    (21, 'TCP', 'FTP', '文件传输控制'),
    (22, 'TCP', 'SSH', '安全远程登录'),
    (23, 'TCP', 'Telnet', '明文远程登录'),
    (25, 'TCP', 'SMTP', '邮件发送'),
    (53, 'TCP/UDP', 'DNS', '域名解析'),
    (67, 'UDP', 'DHCP Server', 'DHCP 服务端'),
    (68, 'UDP', 'DHCP Client', 'DHCP 客户端'),
    (80, 'TCP', 'HTTP', '网页服务'),
    (110, 'TCP', 'POP3', '邮件接收'),
    (123, 'UDP', 'NTP', '网络时间'),
    (137, 'UDP', 'NetBIOS Name', 'Windows 名称服务'),
    (138, 'UDP', 'NetBIOS Datagram', 'Windows 数据报服务'),
    (139, 'TCP', 'NetBIOS Session', 'Windows 会话服务'),
    (143, 'TCP', 'IMAP', '邮件访问'),
    (161, 'UDP', 'SNMP', '网络管理'),
    (389, 'TCP/UDP', 'LDAP', '目录服务'),
    (500, 'UDP', 'IKE / ISAKMP', 'IPsec 密钥交换'),
    (514, 'UDP', 'Syslog', '系统日志传输'),
    (520, 'UDP', 'RIP', '路由信息协议'),
    (546, 'UDP', 'DHCPv6 Client', 'IPv6 DHCP 客户端'),
    (547, 'UDP', 'DHCPv6 Server', 'IPv6 DHCP 服务端'),
    (443, 'TCP', 'HTTPS', '加密网页服务'),
    (443, 'UDP', 'HTTP/3 / QUIC', '基于 QUIC 的网页传输'),
    (445, 'TCP', 'SMB', 'Windows 文件共享'),
    (587, 'TCP', 'SMTP Submission', '邮件提交'),
    (636, 'TCP', 'LDAPS', '加密目录服务'),
    (853, 'TCP/UDP', 'DNS over TLS / QUIC', '加密 DNS'),
    (993, 'TCP', 'IMAPS', '加密 IMAP'),
    (995, 'TCP', 'POP3S', '加密 POP3'),
    (1194, 'UDP', 'OpenVPN', 'OpenVPN 默认端口'),
    (1701, 'UDP', 'L2TP', '二层隧道协议'),
    (1723, 'TCP', 'PPTP', '点到点隧道协议'),
    (1812, 'UDP', 'RADIUS Auth', 'RADIUS 认证'),
    (1813, 'UDP', 'RADIUS Accounting', 'RADIUS 计费'),
    (1883, 'TCP', 'MQTT', 'MQTT 明文连接'),
    (1433, 'TCP', 'MSSQL', 'SQL Server'),
    (1521, 'TCP', 'Oracle', 'Oracle 数据库'),
    (3306, 'TCP', 'MySQL', 'MySQL 数据库'),
    (3478, 'TCP/UDP', 'STUN / TURN', 'NAT 穿透'),
    (3389, 'TCP/UDP', 'RDP', 'Windows 远程桌面'),
    (5432, 'TCP', 'PostgreSQL', 'PostgreSQL 数据库'),
    (5672, 'TCP', 'AMQP', '消息队列'),
    (5900, 'TCP', 'VNC', '远程桌面'),
    (6379, 'TCP', 'Redis', 'Redis 数据库'),
    (6514, 'TCP', 'Syslog TLS', '加密系统日志'),
    (8883, 'TCP', 'MQTTS', 'MQTT TLS 连接'),
    (8080, 'TCP', 'HTTP-alt', '常用备用 HTTP'),
    (8443, 'TCP', 'HTTPS-alt', '常用备用 HTTPS'),
    (9200, 'TCP', 'Elasticsearch', '搜索服务'),
    (9418, 'TCP', 'Git', 'Git 原生协议'),
    (11211, 'TCP/UDP', 'Memcached', '内存缓存服务'),
    (27017, 'TCP', 'MongoDB', 'MongoDB 数据库'),
  ];

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _search.addListener(() {
      _query = _search.text;
      if (mounted) setState(() {});
      _saveDraft();
    });
    _restoreDraft();
  }

  @override
  void dispose() {
    if (_draftLoaded) {
      unawaited(_drafts.save('tool.common_ports', _draftValue()));
    }
    _drafts.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final items = _ports
        .where(
          (item) =>
              (_transport == 'ALL' || item.$2.contains(_transport)) &&
              '${item.$1} ${item.$2} ${item.$3} ${item.$4}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    items.sort((left, right) {
      final port = left.$1.compareTo(right.$1);
      return port != 0 ? port : left.$2.compareTo(right.$2);
    });
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('常用端口')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              children: [
                SearchBar(
                  controller: _search,
                  leading: const Icon(Icons.search),
                  hintText: context.tr('搜索端口或服务'),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'ALL', label: LocalizedText('全部')),
                    ButtonSegment(value: 'TCP', label: Text('TCP')),
                    ButtonSegment(value: 'UDP', label: Text('UDP')),
                  ],
                  selected: {_transport},
                  onSelectionChanged: (value) {
                    setState(() => _transport = value.first);
                    _saveDraft();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: LocalizedText(
                        '${item.$1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    title: LocalizedText(
                      item.$3,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: LocalizedText('${item.$2} · ${item.$4}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showPort(item),
                    onLongPress: () async {
                      await Clipboard.setData(
                        ClipboardData(text: '${item.$1}'),
                      );
                      if (mounted) _showCopied();
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPort((int, String, String, String) item) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(child: Text('${item.$1}')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$3,
                          style: Theme.of(sheetContext).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        LocalizedText('${item.$2} · ${item.$4}'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  openTool(
                    context,
                    'ports',
                    widget.appState,
                    args: ToolRouteArgs(
                      port: item.$1,
                      protocol:
                          item.$2.contains('UDP') && !item.$2.contains('TCP')
                          ? 'udp'
                          : 'tcp',
                      sourceToolId: 'common_ports',
                    ),
                  );
                },
                icon: const Icon(Icons.radar_rounded),
                label: const LocalizedText('使用此端口检测'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: '${item.$1}/${item.$2.toLowerCase()}'),
                  );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (mounted) _showCopied();
                },
                icon: const Icon(Icons.content_copy_rounded),
                label: const LocalizedText('复制端口与协议'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCopied() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      behavior: SnackBarBehavior.floating,
      content: LocalizedText('已复制'),
    ),
  );

  Map<String, Object?> _draftValue() => {
    'query': _search.text,
    'transport': _transport,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.common_ports');
    if (!mounted) return;
    final payload = draft?.payload;
    if (payload != null) {
      _transport = const {'ALL', 'TCP', 'UDP'}.contains(payload['transport'])
          ? payload['transport']! as String
          : 'ALL';
      _search.text = payload['query']?.toString() ?? '';
      _query = _search.text;
    }
    _draftLoaded = true;
    setState(() {});
  }

  void _saveDraft() {
    if (_draftLoaded) {
      _drafts.scheduleSave('tool.common_ports', _draftValue());
    }
  }
}
