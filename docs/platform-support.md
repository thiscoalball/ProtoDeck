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
| BT/BLE debugging | BLE/GATT and RFCOMM | WinRT BLE scan and GATT client; RFCOMM unavailable | BlueZ BLE scan/GATT client; RFCOMM and GATT server limited | No commitment |
| SSH/SFTP/SCP and tunnels | Yes | Yes | Yes | Partial |
| SMB | SMB2/SMB3 | Native UNC/system credentials | Native libsmbclient SMB2/SMB3 helper | Partial |
| Embedded iPerf | libiperf | Bundled executable | Bundled executable | Not implemented |
| App-level traffic attribution | Restricted by Android APIs | PID/connection ownership; exact bytes require a separately shipped ETW helper | `/proc` socket ownership; exact bytes require a separately shipped eBPF helper | Not implemented |

When a feature is unavailable, ProtoDeck should show the missing permission, dependency or platform
limitation and must not generate example results as if they were measured.

## Ubuntu runtime dependencies

The Linux bundle targets Ubuntu 22.04 and 24.04. Install the runtime services and libraries with:

```bash
sudo apt update
sudo apt install bluez libbluetooth3 libsmbclient libsecret-1-0 network-manager
```

For a source build, install the corresponding development packages:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libsecret-1-dev libbluetooth-dev libsmbclient-dev bluez
```

Useful checks:

```bash
systemctl is-active bluetooth
bluetoothctl show
ldconfig -p | grep libsmbclient
```

ProtoDeck detects these dependencies at runtime. Missing services or permissions keep the relevant
run action disabled and expose a repair command; they do not create synthetic scan or connection data.
