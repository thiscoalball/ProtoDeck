import '../../models/platform_capability.dart';

class PlatformCapabilityStrings {
  const PlatformCapabilityStrings({required this.isEnglish});

  final bool isEnglish;

  String get title => isEnglish ? 'Platform capabilities' : '平台能力';
  String get subtitle => isEnglish
      ? 'Runtime support, permissions, dependencies, and recovery actions'
      : '运行能力、权限、系统依赖与修复操作';
  String get detectedAt => isEnglish ? 'Last checked' : '检测时间';
  String get refresh => isEnglish ? 'Check again' : '重新检测';
  String get copyInstallCommand =>
      isEnglish ? 'Copy install command' : '复制安装命令';
  String get copied => isEnglish ? 'Command copied' : '命令已复制';
  String get enableEnhancedMonitoring =>
      isEnglish ? 'Enable enhanced monitoring' : '启用增强监控';

  String name(CapabilityId id) => switch (id) {
    CapabilityId.wifiScan => isEnglish ? 'Wi-Fi scanning' : 'Wi-Fi 扫描',
    CapabilityId.bluetoothClassic => isEnglish ? 'Bluetooth Classic' : '经典蓝牙',
    CapabilityId.bluetoothLowEnergy => isEnglish ? 'Bluetooth LE' : '低功耗蓝牙',
    CapabilityId.smb => isEnglish ? 'SMB file access' : 'SMB 文件访问',
    CapabilityId.interfaceTraffic => isEnglish ? 'Interface traffic' : '网卡流量',
    CapabilityId.processTraffic => isEnglish ? 'Process connections' : '进程连接归属',
    CapabilityId.enhancedProcessTraffic =>
      isEnglish ? 'Enhanced per-app traffic' : '增强应用流量',
    CapabilityId.packetCapture => isEnglish ? 'Packet analysis' : '数据包分析',
  };

  String state(CapabilityState state) => switch (state) {
    CapabilityState.available => isEnglish ? 'Available' : '可用',
    CapabilityState.partial => isEnglish ? 'Limited' : '部分可用',
    CapabilityState.permissionRequired =>
      isEnglish ? 'Permission required' : '需要权限',
    CapabilityState.dependencyMissing =>
      isEnglish ? 'Dependency missing' : '缺少依赖',
    CapabilityState.elevationRequired =>
      isEnglish ? 'Elevation required' : '需要提权',
    CapabilityState.unsupported => isEnglish ? 'Not supported' : '当前平台不支持',
  };

  String reason(String code) => switch (code) {
    'capability.ready' => isEnglish ? 'Ready to use.' : '当前环境已就绪。',
    'capability.notProbed' =>
      isEnglish ? 'This capability has not been checked.' : '尚未检测此能力。',
    'capability.someFeaturesUnavailable' =>
      isEnglish
          ? 'Core functions are available; some platform-specific operations are unavailable.'
          : '核心功能可用，部分平台专属操作暂不可用。',
    'capability.platformUnsupported' =>
      isEnglish
          ? 'This platform does not provide the required integration.'
          : '当前平台没有对应的系统集成。',
    'capability.desktopBluetoothLimited' =>
      isEnglish
          ? 'The desktop Bluetooth bridge is available with platform limitations.'
          : '桌面蓝牙桥接可用，但部分操作受系统限制。',
    'capability.bluetoothRuntimeMissing' =>
      isEnglish
          ? 'The desktop Bluetooth runtime is unavailable.'
          : '桌面蓝牙运行环境不可用。',
    'capability.bluezUnavailable' =>
      isEnglish
          ? 'BlueZ is missing, inactive, or inaccessible.'
          : 'BlueZ 未安装、未运行或当前用户无权访问。',
    'capability.libsmbclientMissing' =>
      isEnglish
          ? 'libsmbclient is required for independent Linux SMB sessions.'
          : 'Linux 独立 SMB 会话需要 libsmbclient。',
    'capability.connectionOwnershipOnly' =>
      isEnglish
          ? 'Connections can be mapped to processes; exact per-process byte counts require enhanced monitoring.'
          : '可以关联连接与进程；精确的进程字节统计需要增强监控。',
    'capability.etwElevationRequired' =>
      isEnglish
          ? 'A separate elevated ETW helper is required. The main application remains unprivileged.'
          : '需要单独启动提权的 ETW 辅助进程，主程序仍保持普通权限。',
    'capability.ebpfElevationRequired' =>
      isEnglish
          ? 'A separate privileged eBPF helper is required. The main application remains unprivileged.'
          : '需要单独启动特权 eBPF 辅助进程，主程序仍保持普通权限。',
    'capability.ebpfRuntimeMissing' =>
      isEnglish
          ? 'The eBPF inspection runtime is not installed.'
          : '尚未安装 eBPF 检测运行环境。',
    'capability.enhancedHelperMissing' =>
      isEnglish
          ? 'This build does not include the isolated enhanced-traffic helper. Regular connection ownership remains available.'
          : '当前构建未包含隔离的增强流量辅助进程，仍可使用普通连接归属模式。',
    'capability.offlineCaptureOnly' =>
      isEnglish
          ? 'Offline PCAP/PCAPNG analysis is available; global VPN capture is not enabled.'
          : '支持离线 PCAP/PCAPNG 分析，尚未启用全局 VPN 抓包。',
    'capability.androidNoEnhancedTraffic' =>
      isEnglish
          ? 'Android exposes app usage statistics instead of the desktop enhanced monitor.'
          : 'Android 使用应用流量统计，不使用桌面增强监控。',
    _ => isEnglish ? 'No additional details.' : '暂无更多说明。',
  };
}
