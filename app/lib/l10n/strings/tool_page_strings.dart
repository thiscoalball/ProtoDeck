import 'tool_page_common_en.dart';
import 'tool_page_additional_en.dart';
import 'tool_page_developer_en.dart';
import 'tool_page_network_en.dart';
import 'tool_page_remote_en.dart';

class ToolPageStrings {
  const ToolPageStrings({required this.isEnglish});

  final bool isEnglish;

  String requestCount(int count) =>
      isEnglish ? '$count requests' : '$count 个请求';
  String timesCount(int count) => isEnglish ? '$count times' : '$count 次';
  String flowCount(int count) => isEnglish ? '$count flows' : '$count 个会话';

  String dnsComparisonSummary({
    required int successful,
    required int total,
    required int answerGroups,
  }) => isEnglish
      ? '$successful/$total resolvers succeeded · $answerGroups distinct answer sets'
      : '$successful/$total 个服务器成功 · $answerGroups 组不同答案';

  String stunStabilitySummary({
    required int samples,
    required int mappings,
    required String averageRtt,
  }) => isEnglish
      ? '$samples probes · $mappings mappings · average RTT $averageRtt ms'
      : '$samples 次探测 · $mappings 个映射 · 平均 RTT $averageRtt ms';

  String tlsAlpnSummary({required String protocols, required int derBytes}) =>
      isEnglish
      ? 'ALPN offered $protocols · certificate DER $derBytes bytes'
      : 'ALPN 提议 $protocols · 证书 DER $derBytes bytes';

  String httpBodyTruncatedSummary({
    required String received,
    required String retained,
  }) => isEnglish
      ? 'Received $received; retained the first $retained'
      : '实际接收 $received，当前仅保留前 $retained';

  String apiResponseDurationDelta(String delta) =>
      isEnglish ? 'Duration $delta' : '耗时 $delta';

  String apiResponseSizeDelta(String delta) =>
      isEnglish ? 'Size $delta' : '大小 $delta';

  String apiResponseChangesSummary({required int headers, required int body}) =>
      isEnglish
      ? '$headers header changes · $body body changes'
      : '$headers 个 Header 变化 · $body 个正文变化';

  String apiResponseChangesTruncated({
    required int shown,
    required int total,
  }) => isEnglish
      ? 'Showing the first $shown of $total changes'
      : '仅展示前 $shown 项变化，共 $total 项';

  String lanScanStrategySummary({
    required int ports,
    required int concurrency,
    required int timeoutMs,
  }) => isEnglish
      ? '$ports TCP ports · concurrency $concurrency · ${timeoutMs}ms'
      : '$ports 个 TCP 端口 · 并发 $concurrency · ${timeoutMs}ms';

  static final _english = <String, String>{
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
    if (source.contains('\n')) {
      return source.split('\n').map(translate).join('\n');
    }
    if ((match = RegExp(r'^目标网卡：(.+)$').firstMatch(source)) != null) {
      return 'Target adapter: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^上次检测：(.+)$').firstMatch(source)) != null) {
      return 'Last checked: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^模板已导出：(.+)$').firstMatch(source)) != null) {
      return 'Templates exported to: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^已导入 (\d+) 个网络配置模板$').firstMatch(source)) != null) {
      return 'Imported ${match!.group(1)} network configuration templates';
    }
    if ((match = RegExp(r'^暂时失败：(.+)$').firstMatch(source)) != null) {
      return 'Temporarily failed: ${match!.group(1)}';
    }
    if ((match = RegExp(
          r'^将 (.+) 恢复到 (.+) 保存的状态。该操作也会短暂中断连接。$',
        ).firstMatch(source)) !=
        null) {
      return 'Restore ${match!.group(1)} to the state saved at ${match.group(2)}. Connectivity may be interrupted briefly.';
    }
    if ((match = RegExp(r'^开放端口：(.+)$').firstMatch(source)) != null) {
      return 'Open ports: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^发现方式：(.+)$').firstMatch(source)) != null) {
      return 'Discovered via: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^(\d+) 个模板 · (\d+) 条历史$').firstMatch(source)) !=
        null) {
      return '${match!.group(1)} templates · ${match.group(2)} history items';
    }
    if ((match = RegExp(r'^(\d+) 个$').firstMatch(source)) != null) {
      return '${match!.group(1)} sessions';
    }
    if ((match = RegExp(r'^(.+) 个端点$').firstMatch(source)) != null) {
      return '${match!.group(1)} endpoints';
    }
    if ((match = RegExp(r'^全部 (.+)$').firstMatch(source)) != null) {
      return 'All ${match!.group(1)}';
    }
    if ((match = RegExp(r'^开放 (.+)$').firstMatch(source)) != null) {
      return 'Open ${match!.group(1)}';
    }
    if ((match = RegExp(r'^异常 (.+)$').firstMatch(source)) != null) {
      return 'Attention ${match!.group(1)}';
    }
    if ((match = RegExp(r'^查询 (.+)$').firstMatch(source)) != null) {
      return 'Query ${match!.group(1)}';
    }
    if ((match = RegExp(r'^解析成功 · (.+) 条$').firstMatch(source)) != null) {
      return 'Resolved · ${match!.group(1)} records';
    }
    if ((match = RegExp(r'^偏移 (.+) ms · RTT (.+) ms$').firstMatch(source)) !=
        null) {
      return 'Offset ${match!.group(1)} ms · RTT ${match.group(2)} ms';
    }
    if ((match = RegExp(r'^峰值 (.+)/s$').firstMatch(source)) != null) {
      return 'Peak ${match!.group(1)}/s';
    }
    if ((match = RegExp(
          r'^根距离 (.+) ms · LI (.+) · NTP v(.+)$',
        ).firstMatch(source)) !=
        null) {
      return 'Root distance ${match!.group(1)} ms · LI ${match.group(2)} · NTP v${match.group(3)}';
    }
    if ((match = RegExp(r'^已复制 (.+) 台设备的 CSV$').firstMatch(source)) != null) {
      return 'Copied CSV for ${match!.group(1)} devices';
    }
    if ((match = RegExp(r'^已复制 (.+) 条端口结果的 CSV$').firstMatch(source)) != null) {
      return 'Copied CSV for ${match!.group(1)} port results';
    }
    if ((match = RegExp(r'^消息 (\d+)$').firstMatch(source)) != null) {
      return 'Message ${match!.group(1)}';
    }
    if ((match = RegExp(r'^匹配数量: (\d+)$').firstMatch(source)) != null) {
      return 'Matches: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^HTML 实体码点无效：(.+)$').firstMatch(source)) != null) {
      return 'Invalid HTML entity code point: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^无法识别 JSONPath：(.+)$').firstMatch(source)) != null) {
      return 'Unrecognized JSONPath: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^Cron (步长|范围)错误：(.+)$').firstMatch(source)) != null) {
      final kind = match!.group(1) == '步长' ? 'step' : 'range';
      return 'Invalid Cron $kind: ${match.group(2)}';
    }
    if ((match = RegExp(r'^每 (\d+) 分钟$').firstMatch(source)) != null) {
      return 'Every ${match!.group(1)} minutes';
    }
    if ((match = RegExp(r'^Base64 解码失败：(.+)$').firstMatch(source)) != null) {
      return 'Base64 decoding failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^URL 解码失败：(.+)$').firstMatch(source)) != null) {
      return 'URL decoding failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^正则表达式错误：(.+)$').firstMatch(source)) != null) {
      return 'Invalid regular expression: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^(.+) 不是有效的 (.+) 进制数$').firstMatch(source)) != null) {
      return '${match!.group(1)} is not a valid base-${match.group(2)} number';
    }
    if ((match = RegExp(r'^长度小于 minLength (.+)$').firstMatch(source)) != null) {
      return 'Length is less than minLength ${match!.group(1)}';
    }
    if ((match = RegExp(r'^长度大于 maxLength (.+)$').firstMatch(source)) != null) {
      return 'Length is greater than maxLength ${match!.group(1)}';
    }
    if ((match = RegExp(r'^不匹配 pattern (.+)$').firstMatch(source)) != null) {
      return 'Does not match pattern ${match!.group(1)}';
    }
    if ((match = RegExp(r'^小于 minimum (.+)$').firstMatch(source)) != null) {
      return 'Less than minimum ${match!.group(1)}';
    }
    if ((match = RegExp(r'^大于 maximum (.+)$').firstMatch(source)) != null) {
      return 'Greater than maximum ${match!.group(1)}';
    }
    if ((match = RegExp(r'^未知 IANA 时区：(.+)$').firstMatch(source)) != null) {
      return 'Unknown IANA time zone: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^状态码等于 (.+)$').firstMatch(source)) != null) {
      return 'Status code equals ${match!.group(1)}';
    }
    if ((match = RegExp(r'^状态码位于 (.+)$').firstMatch(source)) != null) {
      return 'Status code is within ${match!.group(1)}';
    }
    if ((match = RegExp(r'^响应时间小于 (.+) ms$').firstMatch(source)) != null) {
      return 'Response time is less than ${match!.group(1)} ms';
    }
    if ((match = RegExp(r'^Header (.+) 存在$').firstMatch(source)) != null) {
      return 'Header ${match!.group(1)} exists';
    }
    if ((match = RegExp(r'^Header (.+) 等于 (.+)$').firstMatch(source)) != null) {
      return 'Header ${match!.group(1)} equals ${match.group(2)}';
    }
    if ((match = RegExp(r'^正文包含 (.+)$').firstMatch(source)) != null) {
      return 'Body contains ${match!.group(1)}';
    }
    if ((match = RegExp(r'^响应不是 JSON：(.+)$').firstMatch(source)) != null) {
      return 'Response is not JSON: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^订阅 (.+) · QoS (.+)$').firstMatch(source)) != null) {
      return 'Subscribed to ${match!.group(1)} · QoS ${match.group(2)}';
    }
    if ((match = RegExp(r'^取消订阅 (.+)$').firstMatch(source)) != null) {
      return 'Unsubscribed from ${match!.group(1)}';
    }
    if ((match = RegExp(r'^网络基本可用，有 (.+) 项需要关注$').firstMatch(source)) != null) {
      return 'The network is basically usable; ${match!.group(1)} items need attention';
    }
    if ((match = RegExp(
          r'^发现 (\d+) 项故障(?:、(\d+) 项提醒)?，请优先处理红色项目$',
        ).firstMatch(source)) !=
        null) {
      final warnings = match!.group(2);
      return warnings == null
          ? '${match.group(1)} failures found; address the red items first'
          : '${match.group(1)} failures and $warnings warnings found; address the red items first';
    }
    if ((match = RegExp(r'^(.+) · (.+) ms · 丢包 (.+)%$').firstMatch(source)) !=
        null) {
      return '${match!.group(1)} · ${match.group(2)} ms · loss ${match.group(3)}%';
    }
    if ((match = RegExp(
          r'^(.+) 未响应 ICMP；网关可能禁用了 Ping，不等同于断网$',
        ).firstMatch(source)) !=
        null) {
      return '${match!.group(1)} did not answer ICMP; the gateway may block Ping, which does not mean the internet is offline';
    }
    if ((match = RegExp(r'^(.+) 探测受限：(.+)$').firstMatch(source)) != null) {
      return '${match!.group(1)} probe was limited: ${match.group(2)}';
    }
    if ((match = RegExp(r'^(.+) · 系统未提供信号指标$').firstMatch(source)) != null) {
      return '${match!.group(1)} · signal metrics are not available from the system';
    }
    if ((match = RegExp(r'^(.+) 检测到认证门户，请先完成网络登录$').firstMatch(source)) !=
        null) {
      return '${match!.group(1)} detected a captive portal; complete network sign-in first';
    }
    if ((match = RegExp(r'^HTTP 204 探测成功 · (.+) ms$').firstMatch(source)) !=
        null) {
      return 'HTTP 204 probe succeeded · ${match!.group(1)} ms';
    }
    if ((match = RegExp(r'^返回 HTTP (.+)，可能存在认证门户或透明代理$').firstMatch(source)) !=
        null) {
      return 'HTTP ${match!.group(1)} returned; a captive portal or transparent proxy may be present';
    }
    if ((match = RegExp(r'^探测返回 HTTP (.+)$').firstMatch(source)) != null) {
      return 'Probe returned HTTP ${match!.group(1)}';
    }
    if ((match = RegExp(r'^系统报告互联网可用，但探测端点访问失败：(.+)$').firstMatch(source)) !=
        null) {
      return 'The system reports internet access, but the probe endpoint failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^扫描失败：(.+)$').firstMatch(source)) != null) {
      return 'Scan failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^无法识别端口：(.+)$').firstMatch(source)) != null) {
      return 'Unrecognized port: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^端口必须在 1～65535：(.+)$').firstMatch(source)) != null) {
      return 'Port must be between 1 and 65535: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^无法解析 (.+)$').firstMatch(source)) != null) {
      return 'Unable to resolve ${match!.group(1)}';
    }
    if ((match = RegExp(r'^NTP 响应 Mode=(.+)，不是服务器响应$').firstMatch(source)) !=
        null) {
      return 'NTP response mode ${match!.group(1)} is not a server response';
    }
    if ((match = RegExp(
          r"^NTP 服务器拒绝请求（Kiss-o'-Death: (.+)）$",
        ).firstMatch(source)) !=
        null) {
      return "NTP server rejected the request (Kiss-o'-Death: ${match!.group(1)})";
    }
    if ((match = RegExp(r'^DNS 返回 (.+)$').firstMatch(source)) != null) {
      return 'DNS returned ${match!.group(1)}';
    }
    if ((match = RegExp(r'^(.+)（UDP 截断后 TCP）$').firstMatch(source)) != null) {
      return '${match!.group(1)} (TCP after UDP truncation)';
    }
    if ((match = RegExp(
          r'^(FormatException|SocketException|Bad state): (.+)$',
        ).firstMatch(source)) !=
        null) {
      return '${match!.group(1)}: ${translate(match.group(2)!)}';
    }
    if ((match = RegExp(
          r'^(TimeoutException(?: after [^:]+)?): (.+)$',
        ).firstMatch(source)) !=
        null) {
      return '${match!.group(1)}: ${translate(match.group(2)!)}';
    }
    if ((match = RegExp(r'^互联网未验证：(.+)$').firstMatch(source)) != null) {
      return 'Internet not validated: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^响应媒体类型：(.+)$').firstMatch(source)) != null) {
      return 'Response media type: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^(.+) 必须是 JSON Object$').firstMatch(source)) !=
        null) {
      return '${match!.group(1)} must be a JSON object';
    }
    if ((match = RegExp(
          r'^(.+) Base64URL 或 JSON 无效：(.+)$',
        ).firstMatch(source)) !=
        null) {
      return '${match!.group(1)} has invalid Base64URL or JSON: ${match.group(2)}';
    }
    if ((match = RegExp(r'^指定值：(.+)$').firstMatch(source)) != null) {
      return 'Specific value: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^范围：(.+)$').firstMatch(source)) != null) {
      return 'Range: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^范围步进：(.+)$').firstMatch(source)) != null) {
      return 'Stepped range: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^固定值：(.+)$').firstMatch(source)) != null) {
      return 'Fixed value: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^完整匹配: (.*)$').firstMatch(source)) != null) {
      return 'Full match: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^捕获组: (.*)$').firstMatch(source)) != null) {
      return 'Capture groups: ${translate(match!.group(1)!)}';
    }
    if ((match = RegExp(r'^将断开 (.+) 并释放该会话中的连接和输入状态。$').firstMatch(source)) !=
        null) {
      return 'Disconnect ${match!.group(1)} and release its connection and input state.';
    }
    if ((match = RegExp(r'^已向 (.+) 发送 (.+) 个魔术包$').firstMatch(source)) !=
        null) {
      return 'Sent ${match!.group(2)} magic packets to ${match.group(1)}';
    }
    if ((match = RegExp(r'^正在连接 (.+)$').firstMatch(source)) != null) {
      return 'Connecting to ${match!.group(1)}';
    }
    if ((match = RegExp(r'^已向 (.+) 个 Central 发送 Notify$').firstMatch(source)) !=
        null) {
      return 'Sent a notification to ${match!.group(1)} centrals';
    }
    if ((match = RegExp(r'^实时扫描 (.+)$').firstMatch(source)) != null) {
      return 'Live scan ${match!.group(1)}';
    }
    if ((match = RegExp(
          r'^(\d+) 个网络 / (\d+) 个接入点 · (.+)$',
        ).firstMatch(source)) !=
        null) {
      return '${match!.group(1)} networks / ${match.group(2)} access points · ${translate(match.group(3)!)}';
    }
    if ((match = RegExp(
          r'^(\d+) 个 BSSID · (.+) · 最强 (.+) dBm$',
        ).firstMatch(source)) !=
        null) {
      return '${match!.group(1)} BSSIDs · ${match.group(2)} · strongest ${match.group(3)} dBm';
    }
    if ((match = RegExp(r'^(.+) · 纵轴 0 ～ -100 dBm$').firstMatch(source)) !=
        null) {
      return '${translate(match!.group(1)!)} · vertical axis 0 to -100 dBm';
    }
    if ((match = RegExp(
          r'^信道 (.+) · (.+) MHz · 可用频宽 ≤ (.+) MHz$',
        ).firstMatch(source)) !=
        null) {
      return 'Channel ${match!.group(1)} · ${match.group(2)} MHz · usable width ≤ ${match.group(3)} MHz';
    }
    if ((match = RegExp(r'^评分 (.+)$').firstMatch(source)) != null) {
      return 'Score ${match!.group(1)}';
    }
    if ((match = RegExp(r'^Wi‑Fi 连接请求失败：(.+)$').firstMatch(source)) != null) {
      return 'Wi-Fi connection request failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^Wi‑Fi RTT 测距失败：(.+)$').firstMatch(source)) != null) {
      return 'Wi-Fi RTT ranging failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^连接请求已提交：(.+)$').firstMatch(source)) != null) {
      return 'Connection request submitted: ${match!.group(1)}';
    }
    if ((match = RegExp(
          r'^RSSI (.+) dBm · (.+)/(.+) 次有效测量$',
        ).firstMatch(source)) !=
        null) {
      return 'RSSI ${match!.group(1)} dBm · ${match.group(2)}/${match.group(3)} successful measurements';
    }
    if ((match = RegExp(
          r'^信号 (.+)/60 · 拥塞 (.+)/25 · 链路 (.+)/15$',
        ).firstMatch(source)) !=
        null) {
      return 'Signal ${match!.group(1)}/60 · congestion ${match.group(2)}/25 · link ${match.group(3)}/15';
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
    if ((match = RegExp(r'^iPerf3 (.+) 运行中$').firstMatch(source)) != null) {
      return 'iPerf3 ${match!.group(1)} running';
    }
    if ((match = RegExp(r'^服务端已监听 :(.+)$').firstMatch(source)) != null) {
      return 'Server listening on :${match!.group(1)}';
    }
    if ((match = RegExp(
          r'^正在监听 (.+)，等待 iPerf3 Client 连接。$',
        ).firstMatch(source)) !=
        null) {
      return 'Listening on ${match!.group(1)} and waiting for an iPerf3 client.';
    }
    if ((match = RegExp(r'^运行失败：(.+)$').firstMatch(source)) != null) {
      return 'Run failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^\[失败 (.+)\] (.+)$').firstMatch(source)) != null) {
      return '[Failed ${match!.group(1)}] ${translate(match.group(2)!)}';
    }
    if ((match = RegExp(r'^\[停止请求失败：(.+)\]$').firstMatch(source)) != null) {
      return '[Stop request failed: ${match!.group(1)}]';
    }
    if ((match = RegExp(r'^发送失败：(.+)$').firstMatch(source)) != null) {
      return 'Send failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^请求失败：(.+)$').firstMatch(source)) != null) {
      return 'Request failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^响应头格式错误：(.+)$').firstMatch(source)) != null) {
      return 'Invalid response header: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^(.+) 服务正在监听$').firstMatch(source)) != null) {
      return '${match!.group(1)} service is listening';
    }
    if ((match = RegExp(r'^已复制：(.+)$').firstMatch(source)) != null) {
      return 'Copied: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^发现失败：(.+)$').firstMatch(source)) != null) {
      return 'Discovery failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^扫描失败：(.+)$').firstMatch(source)) != null) {
      return 'Scan failed: ${match!.group(1)}';
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
    if ((match = RegExp(r'^(.+):(.+) · (.+)$').firstMatch(source)) != null &&
        source.contains('ALPN')) {
      return '${match!.group(1)}:${match.group(2)} · ${translate(match.group(3)!)}';
    }
    if ((match = RegExp(r'^(IPv[46]) · 解析到 (\d+) 个地址$').firstMatch(source)) !=
        null) {
      return '${match!.group(1)} · ${match.group(2)} resolved addresses';
    }
    if ((match = RegExp(
          r'^DNS (.+) ms · TCP (.+) ms · TLS (.+) ms · 总计 (.+) ms$',
        ).firstMatch(source)) !=
        null) {
      return 'DNS ${match!.group(1)} ms · TCP ${match.group(2)} ms · TLS ${match.group(3)} ms · total ${match.group(4)} ms';
    }
    if ((match = RegExp(
          r'^ALPN 提议 (.+) · 证书 DER (.+) bytes$',
        ).firstMatch(source)) !=
        null) {
      return 'ALPN offered ${match!.group(1)} · certificate DER ${match.group(2)} bytes';
    }
    if ((match = RegExp(r'^有效期 (.+) → (.+)$').firstMatch(source)) != null) {
      return 'Validity ${match!.group(1)} → ${match.group(2)}';
    }
    if ((match = RegExp(r'^已过期 (.+) 天$').firstMatch(source)) != null) {
      return 'Expired ${match!.group(1)} days ago';
    }
    if ((match = RegExp(r'^剩余 (.+) 天$').firstMatch(source)) != null) {
      return '${match!.group(1)} days remaining';
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
    if ((match = RegExp(r'^导入失败：(.+)$').firstMatch(source)) != null) {
      return 'Import failed: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^工作区已导出：(.+)$').firstMatch(source)) != null) {
      return 'Workspace exported: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^返回 (\d+) 个变量$').firstMatch(source)) != null) {
      return '${match!.group(1)} variables returned';
    }
    if ((match = RegExp(r'^(\d+) 条断言 · (\d+) 条提取规则$').firstMatch(source)) !=
        null) {
      return '${match!.group(1)} assertions · ${match.group(2)} extraction rules';
    }
    if ((match = RegExp(
          r'^(\d+)/(\d+) 断言通过 · (\d+)/(\d+) 提取成功$',
        ).firstMatch(source)) !=
        null) {
      return '${match!.group(1)}/${match.group(2)} assertions passed · ${match.group(3)}/${match.group(4)} extractions succeeded';
    }
    if ((match = RegExp(r'^实际：(.+)$').firstMatch(source)) != null) {
      return 'Actual: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^已写入当前会话：(.+)$').firstMatch(source)) != null) {
      return 'Written to this session: ${match!.group(1)}';
    }
    if ((match = RegExp(r'^已加载 (.+)$').firstMatch(source)) != null) {
      return 'Loaded ${match!.group(1)}';
    }
    if ((match = RegExp(r'^已获取 (\d+) 条，页面仅渲染前 1000 条。$').firstMatch(source)) !=
        null) {
      return '${match!.group(1)} rows received; the page renders the first 1000.';
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
      return 'Connection state: ${translate(match!.group(1)!)}';
    }
    if ((match = RegExp(r'^(.+) 条$').firstMatch(source)) != null) {
      return '${translate(match!.group(1)!)} events';
    }
    if ((match = RegExp(r'^(.+) 个连接$').firstMatch(source)) != null) {
      return '${match!.group(1)} connections';
    }
    if ((match = RegExp(r'^(\d+) 次(?: · (.+))?$').firstMatch(source)) != null) {
      final suffix = match!.group(2);
      return '${match.group(1)} times${suffix == null ? '' : ' · ${translate(suffix)}'}';
    }
    if ((match = RegExp(r'^(\d+) 流$').firstMatch(source)) != null) {
      return '${match!.group(1)} streams';
    }
    if ((match = RegExp(r'^对比时区（(\d+)）$').firstMatch(source)) != null) {
      return 'Compared time zones (${match!.group(1)})';
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
    if ((match = RegExp(
          r'^结果共有 (\d+) 行，页面仅显示前 (\d+) 行；复制全部或导出可获得完整结果。$',
        ).firstMatch(source)) !=
        null) {
      return 'The result has ${match!.group(1)} lines. The page shows the first ${match.group(2)}; use Copy all or Export for the complete result.';
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
    if ((match = RegExp(r'^按流量显示前 (.+) 个会话，共 (.+) 个。$').firstMatch(source)) !=
        null) {
      return 'Showing the top ${match!.group(1)} flows by traffic, ${match.group(2)} total.';
    }
    if ((match = RegExp(r'^按流量显示前 (.+) 个端点，共 (.+) 个。$').firstMatch(source)) !=
        null) {
      return 'Showing the top ${match!.group(1)} endpoints by traffic, ${match.group(2)} total.';
    }
    if ((match = RegExp(r'^IPv4-mapped IPv6，内嵌 (.+)$').firstMatch(source)) !=
        null) {
      return 'IPv4-mapped IPv6 with embedded ${match!.group(1)}';
    }
    if (source.contains(' · ')) {
      final parts = source.split(' · ');
      final translated = parts.map(translate).join(' · ');
      if (translated != source) return translated;
    }
    return null;
  }

  static const _phraseReplacements = <(String, String)>[
    (
      '普通模式展示真实接口速率，并将活动 TCP/UDP 端点关联到可见进程。',
      ' regular mode shows real interface rates and maps active TCP/UDP endpoints to visible processes.',
    ),
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
    ('截断的 AD 结构', 'Truncated AD structure'),
    ('设备类型:', 'Device type:'),
    ('配对状态:', 'Pairing state:'),
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
    ('私网或位置未知', 'private network or unknown location'),
    ('丢失', 'loss'),
    ('有效期', 'Validity'),
    ('返回', 'Returned'),
    ('每 2 秒', 'Every 2 seconds'),
    ('并发', 'concurrent'),
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
