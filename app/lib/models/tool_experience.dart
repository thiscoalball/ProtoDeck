enum ToolDraftBehavior {
  /// The page contains no meaningful editable state.
  none,

  /// Non-sensitive editor state is restored after navigation or app restart.
  safeDraft,

  /// A named profile is persisted; secrets live in the platform secure store.
  secureProfile,
}

enum ToolTaskBehavior {
  /// Pure calculation or lookup with no long-running task.
  none,

  /// Work is cancelled when the page is disposed.
  cancelOnExit,

  /// Work remains alive while the application process is alive.
  continueInApp,

  /// Android may promote the task to a user-visible foreground service.
  foregroundCapable,
}

enum ToolTargetKind { host, url, ipAddress, subnet, macAddress, file, text }

/// Product-level behavior shared by catalog, routing, drafts and task handling.
///
/// Keeping this separate from individual pages prevents every tool from making
/// a different decision about persistence, background work and hand-off.
class ToolExperienceProfile {
  const ToolExperienceProfile({
    required this.draftBehavior,
    required this.taskBehavior,
    required this.acceptedTargets,
    required this.relatedToolIds,
  });

  final ToolDraftBehavior draftBehavior;
  final ToolTaskBehavior taskBehavior;
  final Set<ToolTargetKind> acceptedTargets;
  final List<String> relatedToolIds;

  bool accepts(ToolTargetKind kind) => acceptedTargets.contains(kind);
}

const _profileRelations = <String, List<String>>{
  'doctor': ['ping', 'dns', 'traceroute', 'http'],
  'network': ['doctor', 'wifi', 'traffic_monitor'],
  'network_events': ['wifi_roaming', 'traffic_monitor', 'doctor'],
  'wifi': ['wifi_roaming', 'lan', 'doctor'],
  'wifi_roaming': ['wifi', 'ping', 'network_events'],
  'ping': ['traceroute', 'dns', 'ports', 'http'],
  'traceroute': ['ping', 'geoip', 'ownership'],
  'dns': ['ping', 'http', 'tls', 'ownership'],
  'ntp': ['dns', 'ping'],
  'ports': ['ping', 'telnet', 'tls', 'socket_debug'],
  'lan': ['ping', 'ports', 'http', 'smb'],
  'discovery': ['lan', 'ports', 'http'],
  'wol': ['lan', 'oui'],
  'http': ['api_workbench', 'tls', 'dns', 'ping'],
  'api_workbench': ['http', 'tls', 'socket_debug'],
  'path_mtu': ['ping', 'traceroute'],
  'traffic_monitor': ['packet_capture', 'ownership', 'geoip'],
  'packet_capture': ['traffic_monitor', 'ownership', 'dns'],
  'stun': ['socket_debug', 'ping'],
  'tls': ['http', 'dns', 'ownership'],
  'ownership': ['geoip', 'dns', 'traceroute'],
  'telnet': ['ports', 'socket_debug'],
  'socket_debug': ['ports', 'local_server', 'api_workbench'],
  'local_server': ['socket_debug', 'ports', 'http'],
  'syslog': ['socket_debug', 'lan'],
  'snmp': ['lan', 'ports', 'oui'],
  'bluetooth_debug': ['hexdump', 'base64'],
  'iperf': ['ping', 'traffic_monitor', 'path_mtu'],
  'smb': ['lan', 'ports'],
  'subnet': ['wildcard', 'ip_tools', 'lan'],
  'wildcard': ['subnet', 'ip_tools'],
  'ip_tools': ['subnet', 'geoip', 'ownership'],
  'geoip': ['ownership', 'traceroute', 'dns'],
  'oui': ['mac_format', 'lan'],
  'mac_format': ['oui', 'hexdump'],
  'common_ports': ['ports', 'socket_debug'],
  'base64': ['url_codec', 'hexdump', 'hash'],
  'qr': ['url_codec', 'wifi'],
  'url_codec': ['url_parser', 'base64'],
  'timestamp': ['json_query', 'formatter'],
  'regex': ['diff', 'formatter'],
  'radix': ['bits', 'endian'],
  'bits': ['radix', 'endian'],
  'diff': ['formatter', 'regex'],
  'formatter': ['json_query', 'data_convert', 'diff'],
  'hash': ['hexdump', 'base64'],
  'jwt': ['base64', 'timestamp', 'json_query'],
  'generator': ['hash', 'qr'],
  'chmod': ['radix'],
  'unicode': ['html_entity', 'url_codec'],
  'html_entity': ['unicode', 'url_codec'],
  'hexdump': ['base64', 'hash', 'endian'],
  'url_parser': ['url_codec', 'http'],
  'compression': ['base64', 'hexdump'],
  'data_convert': ['formatter', 'json_query'],
  'json_query': ['formatter', 'data_convert'],
  'cron': ['timestamp'],
  'endian': ['radix', 'bits', 'hexdump'],
  'user_agent': ['regex'],
};

const _secureProfileTools = {'api_workbench', 'smb'};
const _noDraftTools = {'doctor', 'network'};
const _foregroundTools = {'iperf', 'traffic_monitor'};
const _appSessionTools = {
  'network_events',
  'wifi_roaming',
  'socket_debug',
  'local_server',
  'syslog',
  'bluetooth_debug',
  'telnet',
  'smb',
  'api_workbench',
};
const _pageTaskTools = {
  'wifi',
  'ping',
  'traceroute',
  'dns',
  'ntp',
  'ports',
  'lan',
  'discovery',
  'http',
  'path_mtu',
  'packet_capture',
  'stun',
  'tls',
  'ownership',
  'snmp',
  'geoip',
  'oui',
};

const _hostTools = {
  'ping',
  'traceroute',
  'dns',
  'ntp',
  'ports',
  'http',
  'path_mtu',
  'stun',
  'tls',
  'ownership',
  'telnet',
  'socket_debug',
  'snmp',
  'iperf',
  'smb',
  'geoip',
};

ToolExperienceProfile toolExperienceFor(String toolId) {
  final taskBehavior = _foregroundTools.contains(toolId)
      ? ToolTaskBehavior.foregroundCapable
      : _appSessionTools.contains(toolId)
      ? ToolTaskBehavior.continueInApp
      : _pageTaskTools.contains(toolId)
      ? ToolTaskBehavior.cancelOnExit
      : ToolTaskBehavior.none;
  final targetKinds = <ToolTargetKind>{
    if (_hostTools.contains(toolId)) ToolTargetKind.host,
    if (toolId == 'http' || toolId == 'api_workbench' || toolId == 'url_parser')
      ToolTargetKind.url,
    if ({'subnet', 'lan', 'wildcard', 'ip_tools'}.contains(toolId))
      ToolTargetKind.subnet,
    if ({'oui', 'mac_format', 'wol'}.contains(toolId))
      ToolTargetKind.macAddress,
    if ({'packet_capture', 'hash', 'hexdump'}.contains(toolId))
      ToolTargetKind.file,
    if ({
      'base64',
      'url_codec',
      'timestamp',
      'regex',
      'radix',
      'bits',
      'diff',
      'formatter',
      'jwt',
      'unicode',
      'html_entity',
      'compression',
      'data_convert',
      'json_query',
      'cron',
      'endian',
      'user_agent',
    }.contains(toolId))
      ToolTargetKind.text,
  };
  return ToolExperienceProfile(
    draftBehavior: _secureProfileTools.contains(toolId)
        ? ToolDraftBehavior.secureProfile
        : _noDraftTools.contains(toolId)
        ? ToolDraftBehavior.none
        : ToolDraftBehavior.safeDraft,
    taskBehavior: taskBehavior,
    acceptedTargets: Set.unmodifiable(targetKinds),
    relatedToolIds: List.unmodifiable(_profileRelations[toolId] ?? const []),
  );
}
