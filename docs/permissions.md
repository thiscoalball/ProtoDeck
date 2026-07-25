# Permissions and online services

ProtoDeck requests permissions only when a related feature needs them. Denying an optional
permission disables or limits that feature; offline calculators and unrelated protocol tools remain
usable.

## Android permissions

| Permission/capability | Why it is used | User-visible effect when unavailable |
|---|---|---|
| Network and Wi-Fi state | Show the active route, addresses, gateway, DNS and Wi-Fi connection | Network details become partial |
| Change Wi-Fi/multicast state | Trigger permitted scans and receive local discovery traffic | Scan/discovery may be unavailable |
| Fine location / nearby Wi-Fi | Read SSID/BSSID and nearby access-point advertisements where Android requires it | SSID or AP list may be hidden |
| Bluetooth scan/connect/advertise | BLE and classic Bluetooth debugging | Bluetooth workbench is disabled |
| Notifications and foreground services | Keep user-started iPerf, transfer and local server tasks visible and stoppable | Background execution may stop |
| Usage access | Read device traffic counters after explicit system authorization | Per-application traffic is unavailable |
| Query installed applications | Resolve traffic UIDs to application labels and icons | Traffic may show only UID/package data |

ProtoDeck does not request root access or broad all-files storage access. File operations use app
directories or user-selected locations where the platform supports a picker.

## Built-in online providers

| Purpose | Default endpoint | Data sent |
|---|---|---|
| Public IPv4/IPv6 | `api4.ipify.org`, `api6.ipify.org` | Source IP inherent to the request |
| GeoIP | `ipwho.is` | IP address or resolved target selected by the user |
| DNS over HTTPS | `dns.alidns.com/dns-query` | DNS question selected by the user |
| IP ownership/RDAP | `rdap.org/ip/` | IP address selected by the user |
| Map tiles | AutoNavi tile endpoint | Tile coordinates, source IP and normal HTTP metadata |
| Connectivity probe | `connect.rom.miui.com/generate_204` | Source IP and normal HTTP metadata |
| OUI update | `standards-oui.ieee.org` | Normal HTTPS request metadata |

Users may configure some providers. Requests made in REST, WebSocket, SSE, MQTT, SSH, SMB, DNS,
SNMP, Syslog and socket tools are sent to the exact targets configured by the user.

## Local listeners

iPerf Server, Syslog receiver, TCP/UDP server and local HTTP/TCP test server can open listening
ports. The selected bind address controls whether the service is reachable only locally or from the
network. Operating-system firewall prompts may appear. Stop the listener after testing and do not
expose it to an untrusted network without understanding the risk.
