import 'tool_copy.dart';

const networkToolStringsEn = <String, ToolCopy>{
  'doctor': ToolCopy(
    'Network Doctor',
    'Diagnose Wi‑Fi, gateway, DNS, and internet issues',
  ),
  'network': ToolCopy(
    'Network Path',
    'Interfaces, gateways, DNS, and public egress',
  ),
  'network_events': ToolCopy(
    'Network Events',
    'Track route, VPN, DNS, gateway, and address changes',
  ),
  'wifi': ToolCopy(
    'Wi‑Fi Analyzer',
    'Current link, nearby access points, and channels',
  ),
  'wifi_roaming': ToolCopy(
    'Wi‑Fi Roaming',
    'BSSID transitions, RSSI, loss, and outage windows',
  ),
  'ping': ToolCopy('Ping', 'ICMP, TCP, UDP Echo, and UDP Probe'),
  'traceroute': ToolCopy(
    'Traceroute',
    'Per-hop latency, addresses, and geolocation',
  ),
  'dns': ToolCopy('DNS Lookup', 'Record types, custom DNS, DoT, and DoH'),
  'ntp': ToolCopy(
    'NTP Query',
    'Offset, jitter, root distance, and source quality',
  ),
  'ports': ToolCopy('Port Check', 'Scan one port, a list, or a bounded range'),
  'lan': ToolCopy('LAN Scanner', 'Discover, filter, and diagnose online hosts'),
  'discovery': ToolCopy('Service Discovery', 'SSDP / UPnP and mDNS / Bonjour'),
  'wol': ToolCopy('Wake-on-LAN', 'Send a magic packet to a LAN device'),
  'http': ToolCopy(
    'HTTP Diagnostics',
    'Status, headers, timing, and response body',
  ),
  'path_mtu': ToolCopy('Path MTU', 'Discover the no-fragment path MTU limit'),
  'traffic_monitor': ToolCopy(
    'Live Traffic',
    'Upload, download, active connections, and protocols',
  ),
  'packet_capture': ToolCopy(
    'Offline Packet Analysis',
    'Protocol hierarchy, I/O, endpoints, and bidirectional flows',
  ),
  'stun': ToolCopy('STUN Mapping', 'Inspect the mapped UDP address and port'),
  'tls': ToolCopy(
    'TLS Certificate',
    'Handshake, trust chain, expiry, and fingerprints',
  ),
  'telnet': ToolCopy(
    'Telnet Terminal',
    'Interactive sessions and basic negotiation',
  ),
  'socket_debug': ToolCopy(
    'TCP / UDP Debugger',
    'Client, server, Hex, and message logs',
  ),
  'local_server': ToolCopy(
    'Local Test Server',
    'Run an HTTP or TCP Echo service on this device',
  ),
  'syslog': ToolCopy('Syslog Receiver', 'Receive device logs over UDP or TCP'),
  'snmp': ToolCopy('SNMP Browser', 'v2c/v3 OID queries, overview, and Walk'),
  'bluetooth_debug': ToolCopy(
    'Bluetooth Debugger',
    'BLE GATT and Classic Bluetooth client / server',
  ),
  'iperf': ToolCopy('iPerf3', 'Client / Server and TCP / UDP tests'),
  'smb': ToolCopy(
    'SMB File Share',
    'Browse and transfer files over SMB2 / SMB3',
  ),
  'ownership': ToolCopy(
    'RDAP / ASN',
    'IP registration and BGP route ownership',
  ),
  'subnet': ToolCopy(
    'Subnet Calculator',
    'IPv4 / IPv6 boundaries and host counts',
  ),
  'wildcard': ToolCopy(
    'Wildcard Mask',
    'Convert subnet masks, wildcards, and CIDR',
  ),
  'ip_tools': ToolCopy(
    'IP & IPv6 Converter',
    'Classification, embedded formats, and formatting',
  ),
  'geoip': ToolCopy(
    'IP Geolocation',
    'Single or batch queries with up to five workers',
  ),
  'oui': ToolCopy(
    'MAC Vendor Lookup',
    'Find vendors by MAC or prefixes by vendor',
  ),
  'mac_format': ToolCopy(
    'MAC Formatter',
    'Convert Linux, Windows, and Cisco formats',
  ),
  'common_ports': ToolCopy(
    'Common Ports',
    'Quick reference for services and protocols',
  ),
};
