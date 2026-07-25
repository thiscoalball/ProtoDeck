class SettingsStrings {
  const SettingsStrings({
    required this.isEnglish,
    required this.pageTitle,
    required this.pageSubtitle,
    required this.language,
    required this.languageSystem,
    required this.languageChinese,
    required this.languageEnglish,
    required this.appearance,
    required this.themeSystem,
    required this.themeLight,
    required this.themeDark,
    required this.ouiDatabase,
    required this.generatedAt,
    required this.records,
    required this.total,
    required this.databaseSize,
    required this.ieeeModifiedAt,
    required this.checkForUpdates,
    required this.restoreBundled,
    required this.ouiSourceNote,
    required this.privacyTitle,
    required this.privacyBody,
    required this.privacyDetails,
    required this.permissionsTitle,
    required this.permissionsBody,
    required this.permissionsDetails,
    required this.openSourceLicenses,
    required this.openSourceLicensesBody,
    required this.platforms,
    required this.connectingIeee,
    required this.ouiUpToDate,
    required this.restoreDialogTitle,
    required this.restoreDialogBody,
    required this.aboutTitle,
    required this.aboutBody,
    required this.copyBuildInfo,
    required this.buildInfoCopied,
    required this.toolDrafts,
    required this.toolDraftsBody,
    required this.clearToolDrafts,
    required this.clearDraftsDialogTitle,
    required this.clearDraftsDialogBody,
    required this.draftsCleared,
    required this.platformCapabilities,
    required this.platformCapabilitiesBody,
  });

  factory SettingsStrings.zh() => const SettingsStrings(
    isEnglish: false,
    pageTitle: '设置',
    pageSubtitle: '外观、语言、离线数据与隐私',
    language: '语言',
    languageSystem: '跟随系统',
    languageChinese: '简体中文',
    languageEnglish: 'English',
    appearance: '外观',
    themeSystem: '跟随系统',
    themeLight: '浅色',
    themeDark: '深色',
    ouiDatabase: 'OUI 厂商数据库',
    generatedAt: '生成时间',
    records: '记录数',
    total: '合计',
    databaseSize: '数据库大小',
    ieeeModifiedAt: 'IEEE 修改时间',
    checkForUpdates: '检查并更新',
    restoreBundled: '恢复 App 内置版本',
    ouiSourceNote: '数据来源：IEEE Registration Authority。仅在用户点击更新时联网；查询始终在本机完成。',
    privacyTitle: '隐私与凭据',
    privacyBody: '本地优先存储；远程密码和 API Key 使用系统安全存储。',
    privacyDetails:
        'ProtoDeck 不包含广告、行为分析或遥测 SDK。运行公网 IP、GeoIP、地图、DoH、RDAP、OUI 更新及用户配置的协议工具时，请求会发送到对应服务。工作区、会话和缓存默认保存在本机，可通过功能内删除或清除应用数据移除。',
    permissionsTitle: '权限与联网服务',
    permissionsBody: '查看 Wi-Fi、蓝牙、使用情况访问和在线 Provider 的用途。',
    permissionsDetails:
        'Wi-Fi/位置：读取当前连接与附近 AP。\n蓝牙：扫描、连接和调试 BT/BLE 设备。\n使用情况访问与应用查询：将流量 UID 解析为应用名称和图标。\n通知与前台服务：保持用户启动的诊断、传输和监听任务可见且可停止。\n\n默认在线服务包括 ipify、ipwho.is、AliDNS、RDAP、高德地图瓦片、连通性探测和 IEEE OUI 更新。拒绝可选权限时，相关功能会明确显示受限。',
    openSourceLicenses: '开源许可证',
    openSourceLicensesBody: '查看 Flutter/Dart 依赖及应用许可证。',
    platforms: 'Android 10+ · Windows 10/11 · Linux 桌面版',
    connectingIeee: '连接 IEEE…',
    ouiUpToDate: 'OUI 数据库已是最新',
    restoreDialogTitle: '恢复内置 OUI 数据库？',
    restoreDialogBody: '这会替换用户手动更新的数据，但不会影响其他设置。',
    aboutTitle: '关于 ProtoDeck',
    aboutBody: '版本、构建渠道与运行平台信息',
    copyBuildInfo: '复制构建信息',
    buildInfoCopied: '构建信息已复制',
    toolDrafts: '工具草稿',
    toolDraftsBody: '保留非敏感输入和显示选项，不会自动重启网络任务。',
    clearToolDrafts: '清除所有工具草稿',
    clearDraftsDialogTitle: '清除所有工具草稿？',
    clearDraftsDialogBody: '这不会删除远程连接配置、OUI 数据或明确保存的安全凭据。',
    draftsCleared: '工具草稿已清除',
    platformCapabilities: '平台能力',
    platformCapabilitiesBody: '查看当前平台的原生支持、权限、依赖和限制。',
  );

  factory SettingsStrings.en() => const SettingsStrings(
    isEnglish: true,
    pageTitle: 'Settings',
    pageSubtitle: 'Appearance, language, offline data, and privacy',
    language: 'Language',
    languageSystem: 'Follow system',
    languageChinese: '简体中文',
    languageEnglish: 'English',
    appearance: 'Appearance',
    themeSystem: 'Follow system',
    themeLight: 'Light',
    themeDark: 'Dark',
    ouiDatabase: 'OUI vendor database',
    generatedAt: 'Generated',
    records: 'Records',
    total: 'Total',
    databaseSize: 'Database size',
    ieeeModifiedAt: 'IEEE modified',
    checkForUpdates: 'Check for updates',
    restoreBundled: 'Restore bundled version',
    ouiSourceNote:
        'Source: IEEE Registration Authority. Network access occurs only when you request an update; lookups always stay on this device.',
    privacyTitle: 'Privacy and credentials',
    privacyBody:
        'Local-first storage; remote passwords and API keys use secure system storage.',
    privacyDetails:
        'ProtoDeck includes no advertising, behavioral analytics, or telemetry SDK. Public-IP, GeoIP, map, DoH, RDAP, OUI update, and user-configured protocol requests are sent to the corresponding service. Workspaces, sessions, and caches stay on this device by default and can be removed in the related feature or by clearing application data.',
    permissionsTitle: 'Permissions and online services',
    permissionsBody:
        'Review why Wi-Fi, Bluetooth, usage access, and online providers are used.',
    permissionsDetails:
        'Wi-Fi/location: inspect the active connection and nearby access points.\nBluetooth: scan, connect, and debug BT/BLE devices.\nUsage access and app query: resolve traffic UIDs to app names and icons.\nNotifications and foreground services: keep user-started diagnostics, transfers, and listeners visible and stoppable.\n\nDefault online services include ipify, ipwho.is, AliDNS, RDAP, AutoNavi map tiles, connectivity probes, and IEEE OUI updates. A denied optional permission is shown as a feature limitation.',
    openSourceLicenses: 'Open-source licenses',
    openSourceLicensesBody:
        'View application and Flutter/Dart dependency licenses.',
    platforms: 'Android 10+ · Windows 10/11 · Linux desktop',
    connectingIeee: 'Connecting to IEEE…',
    ouiUpToDate: 'The OUI database is up to date',
    restoreDialogTitle: 'Restore the bundled OUI database?',
    restoreDialogBody:
        'This replaces manually updated OUI data without changing other settings.',
    aboutTitle: 'About ProtoDeck',
    aboutBody: 'Version, build channel, and runtime platform information',
    copyBuildInfo: 'Copy build information',
    buildInfoCopied: 'Build information copied',
    toolDrafts: 'Tool drafts',
    toolDraftsBody:
        'Keeps non-sensitive input and display options without restarting network tasks.',
    clearToolDrafts: 'Clear all tool drafts',
    clearDraftsDialogTitle: 'Clear all tool drafts?',
    clearDraftsDialogBody:
        'Remote profiles, OUI data, and explicitly saved secure credentials are not removed.',
    draftsCleared: 'Tool drafts cleared',
    platformCapabilities: 'Platform capabilities',
    platformCapabilitiesBody:
        'Review native support, permissions, dependencies, and limitations.',
  );

  String updateComplete(int totalRecords) => isEnglish
      ? 'Update complete · $totalRecords records'
      : '更新完成，共 $totalRecords 条';

  String updateFailed(Object error) => isEnglish
      ? 'Update failed; the existing database was not changed: $error'
      : '更新失败，原数据库未受影响：$error';

  String updateProgress(double progress) {
    if (progress >= 1) return isEnglish ? 'Database ready' : '数据库已就绪';
    if (progress >= .75) return isEnglish ? 'Writing database…' : '正在写入数据库…';
    if (progress >= .7)
      return isEnglish ? 'Parsing IEEE data…' : '正在解析 IEEE 数据…';
    return isEnglish ? 'Downloading IEEE data…' : '正在下载 IEEE 数据…';
  }

  final bool isEnglish;
  final String pageTitle;
  final String pageSubtitle;
  final String language;
  final String languageSystem;
  final String languageChinese;
  final String languageEnglish;
  final String appearance;
  final String themeSystem;
  final String themeLight;
  final String themeDark;
  final String ouiDatabase;
  final String generatedAt;
  final String records;
  final String total;
  final String databaseSize;
  final String ieeeModifiedAt;
  final String checkForUpdates;
  final String restoreBundled;
  final String ouiSourceNote;
  final String privacyTitle;
  final String privacyBody;
  final String privacyDetails;
  final String permissionsTitle;
  final String permissionsBody;
  final String permissionsDetails;
  final String openSourceLicenses;
  final String openSourceLicensesBody;
  final String platforms;
  final String connectingIeee;
  final String ouiUpToDate;
  final String restoreDialogTitle;
  final String restoreDialogBody;
  final String aboutTitle;
  final String aboutBody;
  final String copyBuildInfo;
  final String buildInfoCopied;
  final String toolDrafts;
  final String toolDraftsBody;
  final String clearToolDrafts;
  final String clearDraftsDialogTitle;
  final String clearDraftsDialogBody;
  final String draftsCleared;
  final String platformCapabilities;
  final String platformCapabilitiesBody;
}
