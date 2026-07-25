import 'tool_page_common_en.dart';
import 'tool_page_additional_en.dart';
import 'tool_page_developer_en.dart';
import 'tool_page_network_en.dart';
import 'tool_page_remote_en.dart';

class ToolPageStrings {
  const ToolPageStrings({required this.isEnglish});

  final bool isEnglish;

  static const _english = <String, String>{
    ...toolPageCommonEnglish,
    ...toolPageAdditionalEnglish,
    ...toolPageNetworkEnglish,
    ...toolPageRemoteEnglish,
    ...toolPageDeveloperEnglish,
  };

  String translate(String source) {
    if (!isEnglish || source.isEmpty) return source;
    final exact = _english[source];
    if (exact != null) return exact;

    final dynamic = _translateDynamic(source);
    if (dynamic != null) return dynamic;

    // Dynamic labels often combine a runtime value with one or two stable
    // Chinese phrases. Longest-first replacement keeps those labels useful
    // without coupling the owning page to a large localization object.
    var translated = source;
    for (final entry in _phraseReplacements) {
      translated = translated.replaceAll(entry.$1, entry.$2);
    }
    return translated;
  }

  String? _translateDynamic(String source) {
    RegExpMatch? match;
    if ((match = RegExp(r'^(\d+) 个模板 · (\d+) 条历史$').firstMatch(source)) !=
        null) {
      return '${match!.group(1)} templates · ${match.group(2)} history items';
    }
    if ((match = RegExp(r'^(\d+) 个$').firstMatch(source)) != null) {
      return '${match!.group(1)} sessions';
    }
    if ((match = RegExp(r'^消息 (\d+)$').firstMatch(source)) != null) {
      return 'Message ${match!.group(1)}';
    }
    if ((match = RegExp(r'^将断开 (.+) 并释放该会话中的连接和输入状态。$').firstMatch(source)) !=
        null) {
      return 'Disconnect ${match!.group(1)} and release its connection and input state.';
    }
    if ((match = RegExp(r'^已向 (.+) 发送 (.+) 个魔术包$').firstMatch(source)) !=
        null) {
      return 'Sent ${match!.group(2)} magic packets to ${match.group(1)}';
    }
    if ((match = RegExp(r'^实时扫描 (.+)$').firstMatch(source)) != null) {
      return 'Live scan ${match!.group(1)}';
    }
    if ((match = RegExp(r'^(.+) 秒前$').firstMatch(source)) != null) {
      return '${match!.group(1)} seconds ago';
    }
    if ((match = RegExp(r'^(.+) 分钟前$').firstMatch(source)) != null) {
      return '${match!.group(1)} minutes ago';
    }
    if ((match = RegExp(r'^没有包含“(.+)”的行$').firstMatch(source)) != null) {
      return 'No lines contain “${match!.group(1)}”';
    }
    if ((match = RegExp(r'^参数错误：(.+)$').firstMatch(source)) != null) {
      return 'Invalid parameters: ${translate(match!.group(1)!)}';
    }
    if ((match = RegExp(r'^正在启动 iPerf 3\.21 (.+)…$').firstMatch(source)) !=
        null) {
      return 'Starting iPerf 3.21 ${match!.group(1)}…';
    }
    if ((match = RegExp(r'^发送失败：(.+)$').firstMatch(source)) != null) {
      return 'Send failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^请求失败：(.+)$').firstMatch(source)) != null) {
      return 'Request failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^发现失败：(.+)$').firstMatch(source)) != null) {
      return 'Discovery failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^错误：(.+)$').firstMatch(source)) != null) {
      return 'Error: ${match!.group(1)}';
    }
    if ((match = RegExp(
          r'^(.+)/(.+) · 成功 (.+) · 失败 (.+)$',
        ).firstMatch(source)) !=
        null) {
      return '${match!.group(1)}/${match.group(2)} · ${match.group(3)} succeeded · ${match.group(4)} failed';
    }
    if ((match = RegExp(r'^握手或证书验证失败：(.+)$').firstMatch(source)) != null) {
      return 'Handshake or certificate validation failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^连接失败：(.+)$').firstMatch(source)) != null) {
      return 'Connection failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^应用流量读取失败：(.+)$').firstMatch(source)) != null) {
      return 'Failed to load application traffic: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^操作失败：(.+)$').firstMatch(source)) != null) {
      return 'Operation failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^隧道启动失败：(.+)$').firstMatch(source)) != null) {
      return 'Failed to start tunnel: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^读取目录失败：(.+)$').firstMatch(source)) != null) {
      return 'Failed to read directory: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^读取失败：(.+)$').firstMatch(source)) != null) {
      return 'Failed to load: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^导出失败：(.+)$').firstMatch(source)) != null) {
      return 'Export failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^已下载到 (.+)$').firstMatch(source)) != null) {
      return 'Downloaded to ${match!.group(1)}';
    }
    if ((match = RegExp(r'^已保存：(.+)$').firstMatch(source)) != null) {
      return 'Saved: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^已复制 (.+)$').firstMatch(source)) != null) {
      return '${match!.group(1)} copied';
    }
    if ((match = RegExp(r'^复制路径 (.+)$').firstMatch(source)) != null) {
      return 'Copy path ${match!.group(1)}';
    }
    if ((match = RegExp(r'^复制 (.+)$').firstMatch(source)) != null) {
      return 'Copy ${match!.group(1)}';
    }
    if ((match = RegExp(
          r'^不是有效 JSON：(.+?)(?:（位置 (.+)）)?$',
        ).firstMatch(source)) !=
        null) {
      final offset = match!.group(2);
      return 'Invalid JSON: ${match.group(1)}${offset == null ? '' : ' (at $offset)'}';
    }
    if ((match = RegExp(r'^… 内容过大，仅显示前 (.+) 个字符$').firstMatch(source)) !=
        null) {
      return '… Content is too large; showing the first ${match!.group(1)} characters';
    }
    if ((match = RegExp(r'^删除 (.+)？$').firstMatch(source)) != null) {
      return 'Delete ${match!.group(1)}?';
    }
    if ((match = RegExp(r'^连接状态：(.+)$').firstMatch(source)) != null) {
      return 'Connection state: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^(.+) 条$').firstMatch(source)) != null) {
      return '${translate(match!.group(1)!)} events';
    }
    if ((match = RegExp(r'^(.+) 个连接$').firstMatch(source)) != null) {
      return '${match!.group(1)} connections';
    }
    if ((match = RegExp(r'^事件时间线 (.+)$').firstMatch(source)) != null) {
      return 'Event timeline ${match!.group(1)}';
    }
    if ((match = RegExp(r'^查询 (.+)$').firstMatch(source)) != null) {
      return 'Query ${match!.group(1)}';
    }
    if ((match = RegExp(r'^服务端：(.+)$').firstMatch(source)) != null) {
      return 'Server: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^本地 Socket：(.+)$').firstMatch(source)) != null) {
      return 'Local socket: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^往返耗时：(.+)$').firstMatch(source)) != null) {
      return 'Round-trip time: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^显示前 (.+) 个$').firstMatch(source)) != null) {
      return 'Showing first ${match!.group(1)}';
    }
    if ((match = RegExp(r'^(.+) · 发现 (.+) 台$').firstMatch(source)) != null) {
      return '${match!.group(1)} · found ${match.group(2)} devices';
    }
    if ((match = RegExp(
          r'^文件共有 (.+) 个包，列表保留前 (.+) 个，统计覆盖完整文件。$',
        ).firstMatch(source)) !=
        null) {
      return 'The file contains ${match!.group(1)} packets; the list keeps ${match.group(2)}, while statistics cover the complete file.';
    }
    if ((match = RegExp(
          r'^当前筛选命中 (.+) 个包，为保证流畅仅显示前 500 个。$',
        ).firstMatch(source)) !=
        null) {
      return 'The current filter matches ${match!.group(1)} packets; showing the first 500.';
    }
    return null;
  }

  static const _phraseReplacements = <(String, String)>[
    ('已连接，但保存配置失败：', 'Connected, but saving the profile failed: '),
    ('当前筛选命中', 'Current filter matched'),
    ('为保证流畅仅显示前', 'showing only the first'),
    ('统计覆盖完整文件', 'statistics cover the complete file'),
    ('文件共有', 'File contains'),
    ('列表保留前', 'list keeps the first'),
    ('部分在线归属信息不可用：', 'Some online ownership data is unavailable: '),
    ('限制了全局连接明细', 'limits global connection details'),
    ('Wi‑Fi 信息读取失败：', 'Failed to read Wi‑Fi information: '),
    ('请求头格式错误：', 'Invalid header format: '),
    ('暂不支持操作：', 'Unsupported action: '),
    ('个已登记前缀', 'registered prefixes'),
    ('个环境变量', 'environment variables'),
    ('个接入点', 'access points'),
    ('个变量', 'variables'),
    ('个包', 'packets'),
    ('台设备', 'devices'),
    ('实际 URL：', 'Effective URL: '),
    ('接口上限', 'Interface limit'),
    ('显示前', 'Showing first'),
    ('找到', 'Found'),
    ('发现', 'found'),
    ('偏移', 'Offset'),
    ('数据包', 'Packet'),
    ('TLS 握手', 'TLS handshake'),
    ('有效期', 'Validity'),
    ('返回', 'Returned'),
    ('每 2 秒', 'Every 2 seconds'),
    ('信道', 'Channel'),
    ('建议', 'recommend'),
    ('服务', 'Service'),
    ('写入', 'Write'),
    ('正在建立 SSH', 'Connecting SSH'),
    ('保存配置失败', 'failed to save profile'),
    ('已获取', 'Loaded'),
    ('页面仅渲染前', 'showing first'),
    ('测试', 'Test'),
    ('连接状态', 'Connection state'),
    ('应用优先级', 'Application priority'),
    ('会话上传', 'Session upload'),
    ('会话下载', 'Session download'),
    ('已接收', 'received'),
    ('提取为', 'Extract as'),
    ('网关', 'Gateway'),
    ('拥挤', 'Congestion'),
    ('秒', 's'),
    ('条', 'items'),
    ('个连接', 'connections'),
  ];
}
