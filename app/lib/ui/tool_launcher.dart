import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'pages/remote/smb_browser_page.dart';
import 'pages/tools/common_ports_page.dart';
import 'pages/tools/bluetooth_debug_page.dart';
import 'pages/tools/api_workbench_page.dart';
import 'pages/tools/developer_tool_page.dart';
import 'pages/tools/dns_lookup_page.dart';
import 'pages/tools/geo_ip_page.dart';
import 'pages/tools/http_diagnostic_page.dart';
import 'pages/tools/ip_tools_page.dart';
import 'pages/tools/ip_ownership_page.dart';
import 'pages/tools/iperf_page.dart';
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
import 'pages/tools/subnet_page.dart';
import 'pages/tools/stun_page.dart';
import 'pages/tools/syslog_receiver_page.dart';
import 'pages/tools/socket_debug_page.dart';
import 'pages/tools/snmp_browser_page.dart';
import 'pages/tools/telnet_terminal_page.dart';
import 'pages/tools/traceroute_page.dart';
import 'pages/tools/realtime_traffic_page.dart';
import 'pages/tools/tls_inspection_page.dart';
import 'pages/tools/wifi_analyzer_page.dart';
import 'pages/tools/wifi_roaming_page.dart';
import 'pages/tools/wake_on_lan_page.dart';
import 'pages/tools/wildcard_mask_page.dart';

Future<void> openTool(BuildContext context, String id, AppState state) {
  final page = switch (id) {
    'doctor' => const NetworkDoctorPage(),
    'network' => const NetworkInfoPage(),
    'network_events' => const NetworkEventMonitorPage(),
    'wifi' => const WifiAnalyzerPage(),
    'wifi_roaming' => const WifiRoamingPage(),
    'iperf' => IperfPage(appState: state),
    'smb' => SmbBrowserPage(appState: state),
    'ping' => PingPage(appState: state),
    'traceroute' => TraceroutePage(appState: state),
    'dns' => DnsLookupPage(appState: state),
    'ntp' => const NtpQueryPage(),
    'ports' => PortScanPage(appState: state),
    'lan' => LanScanPage(appState: state),
    'discovery' => const LocalDiscoveryPage(),
    'wol' => const WakeOnLanPage(),
    'http' => HttpDiagnosticPage(appState: state),
    'path_mtu' => const PathMtuPage(),
    'traffic_monitor' => RealtimeTrafficPage(appState: state),
    'packet_capture' => const PacketCapturePage(),
    'stun' => const StunPage(),
    'tls' => const TlsInspectionPage(),
    'ownership' => const IpOwnershipPage(),
    'telnet' => const TelnetTerminalPage(),
    'socket_debug' => const SocketDebugPage(),
    'local_server' => const LocalTestServerPage(),
    'syslog' => const SyslogReceiverPage(),
    'snmp' => const SnmpBrowserPage(),
    'bluetooth_debug' => const BluetoothDebugPage(),
    'api_workbench' => const ApiWorkbenchPage(),
    'subnet' => SubnetPage(appState: state),
    'wildcard' => const WildcardMaskPage(),
    'ip_tools' => const IpToolsPage(),
    'geoip' => GeoIpPage(appState: state),
    'oui' => const OuiLookupPage(),
    'mac_format' => const MacFormatPage(),
    'common_ports' => const CommonPortsPage(),
    'qr' => const QrGeneratorPage(),
    'base64' ||
    'url_codec' ||
    'timestamp' ||
    'regex' ||
    'radix' ||
    'bits' ||
    'diff' ||
    'formatter' => DeveloperToolPage(mode: id),
    'hash' ||
    'jwt' ||
    'generator' ||
    'chmod' ||
    'unicode' ||
    'html_entity' ||
    'hexdump' ||
    'url_parser' ||
    'compression' => DeveloperToolPage(mode: id),
    'data_convert' ||
    'json_query' ||
    'cron' ||
    'endian' ||
    'user_agent' => DeveloperToolPage(mode: id),
    _ => null,
  };
  if (page == null) return Future.value();
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => page));
}
