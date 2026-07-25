import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/ip_tools_service.dart';

class IpToolsPage extends StatefulWidget {
  const IpToolsPage({super.key});
  @override
  State<IpToolsPage> createState() => _IpToolsPageState();
}

class _IpToolsPageState extends State<IpToolsPage> {
  final _service = IpToolsService();
  final _input = TextEditingController(text: '192.168.1.1');
  final _prefix = TextEditingController(text: '64:ff9b::/96');
  String _mode = 'classify';
  String _output = '';
  @override
  void dispose() {
    _input.dispose();
    _prefix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('IP 与 IPv6 转换')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _mode,
          decoration: const InputDecoration(label: LocalizedText('功能')),
          items:
              const {
                    'classify': '地址分类',
                    'v4v6': 'IPv4 → IPv6',
                    'v6v4': 'IPv6 → IPv4',
                    'v6format': 'IPv6 格式化',
                    'v4format': 'IPv4 数值表示',
                    'v6subnet': 'IPv6 子网计算',
                  }.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: LocalizedText(e.value),
                    ),
                  )
                  .toList(),
          onChanged: (v) => setState(() {
            _mode = v!;
            _output = '';
            _input.text = switch (v) {
              'v6format' => '2001:db8::1',
              'v6v4' => '::ffff:192.0.2.1',
              'v6subnet' => '2001:db8::1/48',
              _ => '192.168.1.1',
            };
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(label: LocalizedText('地址或 CIDR')),
        ),
        if (_mode == 'v4v6' || _mode == 'v6v4') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _prefix,
            decoration: const InputDecoration(
              label: LocalizedText('NAT64 /96 前缀'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _run,
          icon: const Icon(Icons.transform),
          label: const LocalizedText('计算'),
        ),
        const SizedBox(height: 16),
        if (_output.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: LocalizedText(
                          '结果',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: _output)),
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
                  SelectableText(
                    _output,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  void _run() {
    try {
      final result = switch (_mode) {
        'classify' => _classify(),
        'v4v6' =>
          _service
              .ipv4ToIpv6(_input.text, nat64Prefix: _prefix.text)
              .entries
              .map((e) => '${e.key}\n${e.value}')
              .join('\n\n'),
        'v6v4' => _extract(),
        'v6format' => _v6Format(),
        'v4format' => _v4Format(),
        'v6subnet' => _v6Subnet(),
        _ => '',
      };
      setState(() => _output = result);
    } on Object catch (e) {
      setState(() => _output = '错误：$e');
    }
  }

  String _classify() {
    final r = _service.classify(_input.text);
    return '地址：${r.address}\n版本：IPv${r.version}\n类别：${r.category}\n公网：${r.isPublic ? '是' : '否'}\n说明：${r.description}';
  }

  String _extract() {
    final r = _service.extractIpv4(_input.text, nat64Prefix: _prefix.text);
    return r == null ? '未识别到受支持的内嵌 IPv4 格式' : '格式：${r.format}\nIPv4：${r.ipv4}';
  }

  String _v6Format() {
    final r = _service.formatIpv6(_input.text);
    return '压缩\n${r.compressed}\n\n展开\n${r.expanded}\n\nip6.arpa\n${r.reverseDns}\n\n128 位十进制\n${r.decimal}\n\n十六进制\n${r.hexadecimal}';
  }

  String _v4Format() {
    final r = _service.representIpv4(_input.text);
    return 'IPv4：${r.address}\n十进制：${r.decimal}\n十六进制：${r.hexadecimal}\n二进制：${r.binary}';
  }

  String _v6Subnet() {
    final r = _service.calculateIpv6Subnet(_input.text);
    return '网络：${r.network}\n起始：${r.firstAddress}\n结束：${r.lastAddress}\n总地址数：${_service.formatBigInt(r.totalAddresses)}${r.slash64Networks == null ? '' : '\n/64 子网数：${_service.formatBigInt(r.slash64Networks!)}'}';
  }
}
