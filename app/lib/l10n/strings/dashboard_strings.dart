class DashboardStrings {
  const DashboardStrings({required this.isEnglish});

  final bool isEnglish;

  String get subtitle =>
      isEnglish ? 'Your portable network workspace' : '你的随身网络工作台';
  String get exploreMore => isEnglish ? 'Explore more' : '探索更多';
  String get allTools => isEnglish ? 'All tools' : '全部工具';
  String get oneTapDiagnosis => isEnglish ? 'Run diagnosis' : '一键诊断';
  String get networkDetails => isEnglish ? 'Network details' : '查看网络详情';
  String get readingNetwork =>
      isEnglish ? 'Reading current network' : '正在读取当前网络';
  String get accessType => isEnglish ? 'Connection' : '接入方式';
  String get signalStrength => isEnglish ? 'Signal strength' : '信号强度';
  String get linkSpeed => isEnglish ? 'Link speed' : '链路速率';
  String get activeAdapters => isEnglish ? 'Active adapters' : '活动网卡';
  String get localAddress => isEnglish ? 'Local address' : '本机地址';
  String get gateway => isEnglish ? 'Gateway' : '网关';
  String get network => isEnglish ? 'Network' : '网络';
  String get internet => isEnglish ? 'Internet' : '互联网';
  String get cellularNetwork => isEnglish ? 'Cellular' : '蜂窝网络';
  String get wiredNetwork => isEnglish ? 'Ethernet' : '有线网络';
  String get currentNetwork => isEnglish ? 'Current network' : '当前网络';
  String get ethernet => isEnglish ? 'Ethernet' : '以太网';
  String get vpnNetwork => isEnglish ? 'VPN network' : 'VPN 网络';
  String get vpnEnabled => isEnglish ? 'VPN enabled' : 'VPN 已启用';
  String get currentWifi => isEnglish ? 'Current Wi‑Fi' : '当前 Wi‑Fi';
  String get waitingForSignal =>
      isEnglish ? 'Waiting for signal samples…' : '等待信号采样…';
  String get ethernetLink => isEnglish ? 'Ethernet link' : '以太网链路';
  String get wifiSignalStrength =>
      isEnglish ? 'Wi‑Fi signal strength' : 'Wi‑Fi 信号强度';
  String get cellularSignalStrength =>
      isEnglish ? 'Cellular signal strength' : '蜂窝信号强度';
  String get cellularSignal => isEnglish ? 'Cellular signal' : '蜂窝信号';
  String get diagnosis => isEnglish ? 'Diagnose' : '诊断';
  String get scan => isEnglish ? 'Scan' : '扫描';
  String get disconnected => isEnglish ? 'Disconnected' : '未连接';
  String get networkProblem => isEnglish ? 'Network issue' : '网络异常';
  String get limitedConnection => isEnglish ? 'Limited' : '连接受限';
  String get connectionNormal => isEnglish ? 'Connected' : '连接正常';
  String get lanAvailable => isEnglish ? 'LAN available' : '局域网可用';
  String get excellent => isEnglish ? 'Excellent' : '极佳';
  String get good => isEnglish ? 'Good' : '良好';
  String get fair => isEnglish ? 'Fair' : '一般';
  String get weak => isEnglish ? 'Weak' : '较弱';
  String get veryWeak => isEnglish ? 'Very weak' : '很弱';

  String channel(int value) => isEnglish ? 'Channel $value' : '信道 $value';
  String wifiBars(int value) =>
      isEnglish ? 'Wi‑Fi signal, $value bars' : 'Wi-Fi 信号 $value 格';
  String cellularBars(int value) =>
      isEnglish ? 'Cellular signal, $value bars' : '蜂窝信号 $value 格';

  String connectionStatus({
    required String? dnsStatus,
    required String? internetStatus,
    required bool running,
    required bool validated,
    required bool connected,
    required bool loading,
  }) {
    if (internetStatus == 'failed') {
      return isEnglish ? 'Internet unavailable' : '互联网不可用';
    }
    if (dnsStatus == 'failed') return isEnglish ? 'DNS issue' : 'DNS 异常';
    if (internetStatus == 'warning') {
      return isEnglish ? 'Internet check warning' : '互联网探测异常';
    }
    if (dnsStatus == 'warning') {
      return isEnglish ? 'DNS needs attention' : 'DNS 需要关注';
    }
    if (internetStatus == 'passed') {
      return isEnglish ? 'Internet connected' : '互联网已连接';
    }
    if (running) return isEnglish ? 'Checking connectivity' : '连通性检测中';
    if (validated) return isEnglish ? 'Internet pending' : '互联网待确认';
    if (connected) return isEnglish ? 'Network connected' : '当前网络已连接';
    if (loading) return isEnglish ? 'Loading' : '读取中';
    return disconnected;
  }
}
