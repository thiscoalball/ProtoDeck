import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

class CommonPortsPage extends StatefulWidget {
  const CommonPortsPage({super.key});

  @override
  State<CommonPortsPage> createState() => _CommonPortsPageState();
}

class _CommonPortsPageState extends State<CommonPortsPage> {
  var _query = '';

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
    (143, 'TCP', 'IMAP', '邮件访问'),
    (161, 'UDP', 'SNMP', '网络管理'),
    (389, 'TCP/UDP', 'LDAP', '目录服务'),
    (443, 'TCP', 'HTTPS', '加密网页服务'),
    (445, 'TCP', 'SMB', 'Windows 文件共享'),
    (587, 'TCP', 'SMTP Submission', '邮件提交'),
    (636, 'TCP', 'LDAPS', '加密目录服务'),
    (1433, 'TCP', 'MSSQL', 'SQL Server'),
    (1521, 'TCP', 'Oracle', 'Oracle 数据库'),
    (3306, 'TCP', 'MySQL', 'MySQL 数据库'),
    (3389, 'TCP/UDP', 'RDP', 'Windows 远程桌面'),
    (5432, 'TCP', 'PostgreSQL', 'PostgreSQL 数据库'),
    (5900, 'TCP', 'VNC', '远程桌面'),
    (6379, 'TCP', 'Redis', 'Redis 数据库'),
    (8080, 'TCP', 'HTTP-alt', '常用备用 HTTP'),
    (8443, 'TCP', 'HTTPS-alt', '常用备用 HTTPS'),
    (9200, 'TCP', 'Elasticsearch', '搜索服务'),
    (27017, 'TCP', 'MongoDB', 'MongoDB 数据库'),
  ];

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final items = _ports
        .where(
          (item) => '${item.$1} ${item.$2} ${item.$3} ${item.$4}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('常用端口')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              leading: const Icon(Icons.search),
              hintText: context.tr('搜索端口或服务'),
              onChanged: (value) => setState(() => _query = value),
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
                    trailing: IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: '${item.$1}')),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
