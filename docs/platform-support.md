# Platform support

This matrix describes intended support, not a guarantee that every operating-system build exposes
the same information. Permissions, hardware, network policy and installed system tools still apply.

| Capability | Android 10+ | Windows 10/11 | Ubuntu 22.04/24.04 | iOS |
|---|---:|---:|---:|---:|
| IP, DNS, TCP/UDP and offline developer tools | Yes | Yes | Yes | Partial |
| ICMP/Traceroute | Yes | Yes | System-tool dependent | Partial |
| Wi-Fi connection details | Yes | Yes | NetworkManager dependent | Partial |
| Nearby Wi-Fi analysis | Yes, permission/throttling applies | WLAN snapshot | Platform dependent | No commitment |
| Cellular radio metrics | Yes, device/carrier dependent | N/A | N/A | No commitment |
| BT/BLE debugging | Yes, permission/hardware dependent | Not implemented | Not implemented | No commitment |
| SSH/SFTP/SCP and tunnels | Yes | Yes | Yes | Partial |
| SMB | SMB2/SMB3 | Windows integration | Cross-platform client | Partial |
| Embedded iPerf | libiperf | Bundled executable | Bundled executable | Not implemented |
| App-level traffic attribution | Restricted by Android APIs | OS visibility dependent | OS visibility dependent | Not implemented |

When a feature is unavailable, ProtoDeck should show the missing permission, dependency or platform
limitation and must not generate example results as if they were measured.
