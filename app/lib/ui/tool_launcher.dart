import 'package:flutter/material.dart';

import '../models/tool_route_args.dart';
import '../state/app_state.dart';
import 'pages/remote/smb_browser_page.dart';
import 'pages/tools/common_ports_page.dart';
import 'pages/tools/cron_workbench_page.dart';
import 'pages/tools/bluetooth_debug_page.dart';
import 'pages/tools/api_workbench_page.dart';
import 'pages/tools/backend_engineering_page.dart';
import 'pages/tools/developer_tool_page.dart';
import 'pages/tools/dns_lookup_page.dart';
import 'pages/tools/geo_ip_page.dart';
import 'pages/tools/http_diagnostic_page.dart';
import 'pages/tools/ip_tools_page.dart';
import 'pages/tools/ip_ownership_page.dart';
import 'pages/tools/iperf_page.dart';
import 'pages/tools/jwt_workbench_page.dart';
import 'pages/tools/lan_scan_page.dart';
import 'pages/tools/local_discovery_page.dart';
import 'pages/tools/local_test_server_page.dart';
import 'pages/tools/mac_format_page.dart';
import 'pages/tools/network_info_page.dart';
import 'pages/tools/network_event_monitor_page.dart';
import 'pages/tools/network_doctor_page.dart';
import 'pages/tools/ntp_query_page.dart';
import 'pages/tools/oui_lookup_page.dart';
import 'pages/tools/ping_page.dart';
import 'pages/tools/path_mtu_page.dart';
import 'pages/tools/packet_capture_page.dart';
import 'pages/tools/port_scan_page.dart';
import 'pages/tools/qr_generator_page.dart';
import 'pages/tools/regex_workbench_page.dart';
import 'pages/tools/subnet_page.dart';
import 'pages/tools/stun_page.dart';
import 'pages/tools/structured_data_workbench_page.dart';
import 'pages/tools/syslog_receiver_page.dart';
import 'pages/tools/socket_debug_page.dart';
import 'pages/tools/snmp_browser_page.dart';
import 'pages/tools/telnet_terminal_page.dart';
import 'pages/tools/traceroute_page.dart';
import 'pages/tools/timestamp_workbench_page.dart';
import 'pages/tools/realtime_traffic_page.dart';
import 'pages/tools/tls_inspection_page.dart';
import 'pages/tools/wifi_analyzer_page.dart';
import 'pages/tools/wifi_roaming_page.dart';
import 'pages/tools/wake_on_lan_page.dart';
import 'pages/tools/wildcard_mask_page.dart';

Future<void> openTool(
  BuildContext context,
  String id,
  AppState state, {
  ToolRouteArgs? args,
}) {
  final page = buildToolPage(id, state, args: args);
  if (page == null) return Future.value();
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => page));
}

@visibleForTesting
Widget? buildToolPage(
  String id,
  AppState state, {
  ToolRouteArgs? args,
}) => switch (id) {
  'doctor' => NetworkDoctorPage(appState: state),
  'network' => const NetworkInfoPage(),
  'network_events' => const NetworkEventMonitorPage(),
  'wifi' => WifiAnalyzerPage(appState: state),
  'wifi_roaming' => const WifiRoamingPage(),
  'iperf' => IperfPage(appState: state),
  'smb' => SmbBrowserPage(appState: state, initialHost: args?.normalizedTarget),
  'ping' => PingPage(appState: state, initialHost: args?.normalizedTarget),
  'traceroute' => TraceroutePage(
    appState: state,
    initialHost: args?.normalizedTarget,
  ),
  'dns' => DnsLookupPage(appState: state, initialHost: args?.normalizedTarget),
  'ntp' => NtpQueryPage(appState: state),
  'ports' => PortScanPage(
    appState: state,
    initialHost: args?.normalizedTarget,
    initialPort: args?.port,
  ),
  'lan' => LanScanPage(appState: state),
  'discovery' => LocalDiscoveryPage(appState: state),
  'wol' => WakeOnLanPage(appState: state, initialMac: args?.normalizedTarget),
  'http' => HttpDiagnosticPage(appState: state, initialUrl: args?.httpUrl),
  'path_mtu' => PathMtuPage(
    appState: state,
    initialHost: args?.normalizedTarget,
  ),
  'traffic_monitor' => RealtimeTrafficPage(appState: state),
  'packet_capture' => PacketCapturePage(appState: state),
  'stun' => StunPage(appState: state),
  'tls' => TlsInspectionPage(
    appState: state,
    initialHost: args?.normalizedTarget,
  ),
  'ownership' => IpOwnershipPage(
    appState: state,
    initialTarget: args?.normalizedTarget,
  ),
  'telnet' => TelnetTerminalPage(
    appState: state,
    initialHost: args?.normalizedTarget,
  ),
  'socket_debug' => SocketDebugPage(appState: state),
  'local_server' => LocalTestServerPage(appState: state),
  'syslog' => SyslogReceiverPage(appState: state),
  'snmp' => SnmpBrowserPage(appState: state),
  'bluetooth_debug' => BluetoothDebugPage(appState: state),
  'api_workbench' => const ApiWorkbenchPage(),
  'subnet' => SubnetPage(appState: state),
  'wildcard' => WildcardMaskPage(appState: state),
  'ip_tools' => IpToolsPage(
    appState: state,
    initialInput: args?.normalizedTarget,
  ),
  'geoip' => GeoIpPage(appState: state),
  'oui' => OuiLookupPage(appState: state, initialMac: args?.normalizedTarget),
  'mac_format' => MacFormatPage(appState: state),
  'common_ports' => CommonPortsPage(appState: state),
  'qr' => QrGeneratorPage(appState: state),
  'timestamp' => TimestampWorkbenchPage(appState: state),
  'regex' => RegexWorkbenchPage(appState: state),
  'formatter' => StructuredDataWorkbenchPage(
    appState: state,
    initialMode: 'format',
  ),
  'data_convert' => StructuredDataWorkbenchPage(
    appState: state,
    initialMode: 'convert',
  ),
  'json_query' => StructuredDataWorkbenchPage(
    appState: state,
    initialMode: 'query',
  ),
  'json_workbench' => StructuredDataWorkbenchPage(appState: state),
  'sql_toolkit' ||
  'id_inspector' ||
  'semver' ||
  'http_metadata' ||
  'log_inspector' => BackendEngineeringPage(mode: id, appState: state),
  'jwt' => JwtWorkbenchPage(appState: state),
  'cron' => CronWorkbenchPage(appState: state),
  'base64' ||
  'url_codec' ||
  'radix' ||
  'bits' ||
  'diff' => DeveloperToolPage(mode: id, appState: state),
  'hash' ||
  'generator' ||
  'chmod' ||
  'unicode' ||
  'html_entity' ||
  'hexdump' ||
  'url_parser' ||
  'compression' => DeveloperToolPage(mode: id, appState: state),
  'endian' || 'user_agent' => DeveloperToolPage(mode: id, appState: state),
  _ => null,
};
