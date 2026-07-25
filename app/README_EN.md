# ProtoDeck Flutter application

<p align="center">
  <a href="README.md">简体中文</a> · <strong>English</strong>
</p>

This directory contains the ProtoDeck Flutter application. Android, Windows,
and Linux share the same domain model and UI foundation while native plugins
provide real networking, Wi-Fi, Bluetooth, file, and traffic capabilities.
The iOS project is currently an experimental target and is not part of the
complete delivery scope.

> Start with the [repository README](../README_EN.md) for the project overview,
> screenshots, and contribution entry points. This document focuses on the app
> catalog, architecture, platform boundaries, builds, and development rules.

## Feature catalog

The catalog currently contains 65 entries in nine categories. Features that
require permissions, external commands, or native APIs are checked by the
capability center. Unavailable tools explain the reason and recovery path and
never return fabricated success data.

### Wi-Fi

- **Network Path:** default route, active interfaces, IPv4/IPv6, gateway, DNS,
  MTU, VPN, and public egress.
- **Wi-Fi Analyzer:** current connection and nearby APs, SSID/BSSID, RSSI,
  bands, channels, security, signal history, occupancy, and recommendations.
- **Wi-Fi Roaming:** BSSID transitions, RSSI, packet loss, transition time,
  and outage windows.

### Network diagnostics

- **Network Doctor:** layered local-link, gateway, DNS, and internet checks.
- **Network Events:** default route, VPN, BSSID, DNS, gateway, and address changes.
- **Ping:** ICMPv4/v6, TCP, UDP Echo, and UDP Probe with count/continuous modes,
  intervals, timeout, payload, IP version, live latency chart, and summaries.
- **Traceroute:** per-hop latency, address, hostname, GeoIP, and an ordered route map.
- **DNS:** A, AAAA, CNAME, MX, TXT, NS, PTR, custom DNS, DoT, and DoH.
- **NTP:** server time, offset, RTT, jitter, Stratum, root distance, and quality.
- **Ports and LAN:** single/list/range port scans, host discovery, and tool handoff.
- **Discovery and path tools:** SSDP/UPnP, mDNS/Bonjour, Wake-on-LAN, Path MTU, and STUN.

### Traffic and performance

- **Live Traffic:** interface charts, endpoints, protocol distribution, and
  desktop PID/process attribution with an explicit confidence level.
- **Offline Packet Analysis:** PCAP/PCAPNG protocol hierarchy, I/O, endpoints,
  and bidirectional sessions without a global VPN capture mode.
- **iPerf3:** bundled client/server, TCP/UDP, IPv4/IPv6, reverse/bidirectional,
  parallel streams, bitrate, live console, and throughput charts. Command input
  parses an allowlist and never executes an arbitrary shell.

### Remote and services

- **SSH:** password/key authentication, PTY, multiple sessions, TOFU host keys,
  ANSI terminal, special keys, and Local/Remote/Dynamic SOCKS tunnels. Moving
  between pages does not disconnect an active app-session connection.
- **Remote files:** prefer SFTP and fall back to SCP/Shell browsing when the
  server lacks an SFTP subsystem. Includes transfer, mkdir, delete, rename,
  chmod, progress, and stable name/size/time sorting.
- **SMB:** SMB2/SMB3 via SMBJ on Android, UNC on Windows, and libsmbclient on Linux.
- **Protocols and services:** Telnet, TCP/UDP debugger, UDP/TCP Syslog receiver,
  SNMP v2c/v3 browser, and local HTTP/TCP Echo servers.
- **Bluetooth:** BLE scanning, GATT service/characteristic browsing, read/write,
  and notifications; Classic Bluetooth and server modes are capability-gated.

### API and protocols

- **API Workbench:** REST collections, parameters, Headers, Cookies, Auth,
  Body, environments, assertions, and extraction; WebSocket messages, SSE
  events, and MQTT subscriptions/publishing are included in the same workspace.
- **HTTP Diagnostics:** status, timing, Headers, and content-type-aware JSON,
  XML, HTML, text, and binary response views.
- **Protocol helpers:** TLS chains/fingerprints, URL codec/parser, User-Agent,
  and HTTP cache/Cookie/CORS/security metadata.

### IP and addressing

- IPv4/IPv6 subnet boundaries, usable hosts, broadcast, wildcard masks, and
  `/31`/`/32` edge behavior.
- Address classification, mapped/compatible/6to4/NAT64/translatable forms,
  IPv6 compression/expansion, `ip6.arpa`, and numeric forms.
- Single/batch GeoIP, RDAP/ASN/BGP ownership, and common-port reference.
- Offline IEEE MA-L/MA-M/MA-S OUI lookup, reverse vendor search,
  longest-prefix matching, and manual atomic updates.
- Linux, Windows, Cisco, and plain MAC formatting.

### Data and conversion

- Base64, QR, timestamp/time zones/batch conversion, Regex presets/groups/
  replacement, radix 2–36, and bit operations.
- Text Diff, JSON/XML/YAML/SQL formatting, Unicode, HTML entities, Hexdump, and Gzip.
- JSON/YAML/CSV conversion, JSONPath, pragmatic JSON Schema validation,
  semantic Diff, model generation, endian, and integer inspection.

### Security and identifiers

- Text/file Hash, HMAC, and per-result copy actions.
- JWT decoding and time-claim checks; UUID v4, ULID, and secure passwords.
- UUID, ULID, ObjectId, and Snowflake inspection plus chmod octal/rwx conversion.

### Backend engineering

- Cron explanation and future schedules.
- SQL formatting, IN lists, and INSERT generation from JSON.
- Semantic Version validation and prerelease precedence.
- JSON Lines, log-level, Trace ID, and ANSI log analysis.

## UX and data rules

- Primary navigation is Home, Wi-Fi, Tools, and Remote. Settings opens from
  Home; there is no separate History primary destination.
- Phones use compact cards and bottom navigation. Desktop uses a grouped
  sidebar, wide content canvas, and mouse/keyboard-friendly controls.
- `ToolDraftRepository` debounces non-sensitive form state. Reopening a page or
  restarting the app can restore inputs, tabs, filters, and sort options, but
  never automatically restarts Ping, scans, services, or capture tasks.
- Passwords, tokens, cookies, and private-key passphrases are excluded from
  ordinary drafts. Only explicitly saved credentials use platform secure storage.
- SSH and SMB registries keep active sessions alive within the current process;
  after an app restart, entries return without automatic reconnection.
- User-facing strings use modular English and Chinese resources. SSIDs, vendor
  names, protocol samples, and remote logs remain unmodified.
- Desktop bundles include the Apache-2.0-licensed Droid Sans Fallback for CJK
  glyph coverage; its license is stored alongside the font asset.

## Architecture and layout

```text
app/
├── android/                Kotlin platform services and native capabilities
├── ios/                    Experimental iOS Runner
├── linux/                  GTK, BlueZ, libsmbclient, and desktop system bridge
├── windows/                Win32/WinRT, WLAN, Bluetooth, UNC, and network bridge
├── assets/                 Fonts, bundled data, and licenses
├── lib/
│   ├── core/               Shared infrastructure and core utilities
│   ├── data/               Drift, repositories, cache, and secure storage
│   ├── models/             Cross-platform models and structured failures
│   ├── services/           Networking, remote, parsing, conversion, and tasks
│   ├── state/              Riverpod providers, registries, and app state
│   ├── ui/                 Home, catalog, remote, settings, and tool pages
│   └── l10n/               Modular English and Chinese resources
├── test/                   Unit, widget, localization, and regression tests
└── tool/                   OUI, screenshots, desktop dependencies, and packaging
```

Flutter/Dart owns cross-platform UI and portable tools. Riverpod manages
dependencies and state, go_router manages navigation, and Drift/SQLite stores
drafts, cache, and structured data. Android uses Kotlin; Windows uses C++ with
WinRT/Win32; Linux uses GTK, D-Bus/BlueZ, libsmbclient, `/proc`, and system
commands. Native calls return error codes and technical details, while Flutter
localizes user-facing messages.

See [architecture](../docs/architecture.md) and
[platform support](../docs/platform-support.md) for more detail.

## Capability matrix

| Capability | Android 10+ | Windows 10/11 x64 | Ubuntu 22.04/24.04 | iOS |
|---|---|---|---|---|
| Current network/route/DNS | Native | System APIs | NetworkManager/iproute2 | Experimental |
| Wi-Fi connection/scans | Native, permission and throttle limited | WLAN API, some cached values | NetworkManager/iw | Experimental |
| BLE | Scan, GATT Client/Server | WinRT scan and GATT Client | BlueZ scan and GATT Client | Experimental |
| Classic Bluetooth/RFCOMM | Permission limited | Currently unavailable | Partially available via BlueZ | Experimental |
| SMB | SMBJ | UNC/system credentials | libsmbclient | Not promised |
| Process traffic attribution | UID/application metadata | PID/active endpoints | PID/socket correlation | Not promised |
| SSH/SFTP/API/IP tools | Supported | Supported | Supported | Experimental |
| iPerf3 | Integrated | Bundled | Bundled | Not promised |

Entries remain visible when a capability is unavailable. The capability center
labels availability, partial support, missing permission/dependency, required
elevation, or unsupported state and provides recovery actions.

## Development environment

CI currently pins Flutter 3.44.8. A compatible Flutter stable release may be
used locally, but analysis and tests should match the workflow before a change
is submitted.

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

Device and network features still require real target-system validation. Unit
tests cannot prove Wi-Fi scans, Bluetooth, firewall rules, credentials, or
platform commands work on a particular machine.

## Android build

Android requires API 29+, JDK 17, and an Android SDK with accepted licenses.

```bash
flutter doctor
flutter pub get
flutter build apk --release --no-pub
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

A server cannot directly access a USB phone attached to your PC. Download the
APK to the PC, run `adb devices`, then `adb install -r app-release.apk`.
Hot reload requires Flutter and the Android SDK on the PC that owns the device.

## Windows build

Install Flutter and Visual Studio's **Desktop development with C++** workload,
including MSVC, CMake, and the Windows SDK.

```powershell
flutter config --enable-windows-desktop
flutter doctor
flutter pub get
flutter build windows --release
./tool/build_bundled_iperf_windows.ps1 `
  -OutputDirectory build/windows/x64/runner/Release
Compress-Archive `
  -Path build/windows/x64/runner/Release/* `
  -DestinationPath build/ProtoDeck-windows-x64.zip `
  -Force
```

Distribute the entire Release directory, not only the EXE. iPerf 3.21 and its
required `cygwin1.dll` are bundled. Windows Desktop can only be built on a
Windows host; Linux does not produce a substitute EXE.

## Linux build

Ubuntu 22.04/24.04 or compatible Debian-based systems require:

```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libsecret-1-dev libsmbclient-dev libbluetooth-dev bluez
flutter config --enable-linux-desktop
flutter pub get
flutter run -d linux
```

Build a Release bundle with:

```bash
./tool/build_linux_release_local.sh
```

On a build host without sudo, use the repository bootstrap:

```bash
./tool/bootstrap_linux_build_deps.sh
./tool/build_linux_release_local.sh
```

The target system needs GTK3, BlueZ, libsmbclient, NetworkManager/iproute2,
`iputils-ping`, and `traceroute` or `tracepath`. iPerf 3.21 is bundled. Missing
services, adapters, libraries, or commands are reported by the capability center.

## Version identity and GitHub Actions

The About page shows semantic version, build number, channel, short Git SHA,
platform, and architecture.

| Trigger | Flutter mode | App channel | Version source | Platforms |
|---|---|---|---|---|
| Push `v0.0.1` tag | Release | `Release` | `0.0.1` from tag | Android, Linux, Windows |
| Manual Actions run | Release | `Debug` | Input or `pubspec.yaml` | Selected platforms |
| Local test firmware | Release | `Debug` | `--build-name` | Host-supported targets |
| `flutter run` | Debug/Profile | `Debug` | `pubspec.yaml` | Current device |

`Debug` is the internal channel identity; manually built artifacts still use
Flutter Release optimization.

```bash
git tag v0.0.1
git push origin v0.0.1

flutter build apk --release --no-pub \
  --build-name 0.0.1 --build-number 1 \
  --dart-define BUILD_CHANNEL=debug --dart-define GIT_SHA=local

flutter build linux --release --no-pub \
  --build-name 0.0.1 --build-number 1 \
  --dart-define BUILD_CHANNEL=debug --dart-define GIT_SHA=local
```

The **Build platform artifacts** workflow supports manual platform selection;
tag builds force all three platforms. Each artifact includes a `.sha256` and
is retained for 14 days in the workflow run's **Artifacts** section.

## Offline OUI database

The app packages the generated SQLite database, not raw CSV files. Build it
from the IEEE MA-L, MA-M, and MA-S sources with:

```bash
dart run tool/oui/build_oui_database.dart
```

The script validates headers, Registry values, prefix lengths, hexadecimal
format, record-count changes, SHA-256, and SQLite integrity. Runtime updates
use a private staging directory, the same validation, sample queries, and an
atomic same-filesystem replacement with rollback.

## Tests and quality gates

High-risk coverage includes IPv4/IPv6 boundaries, OUI update/rollback,
task cancellation, Wi-Fi/Bluetooth permissions and degradation, SSH keys and
active sessions, file sorting/transfers, API drafts and realtime histories,
content-type-aware responses, and translation key/signature consistency.

```bash
flutter analyze --no-pub
flutter test --no-pub
git diff --check
```

## Documentation screenshots

Screenshots are generated from reproducible Flutter widget scenes:

```bash
./tool/generate_docs_screenshots.sh
```

Output is written to `../docs/screenshots/`. Review text overflow, viewport
layout, and both languages when UI changes alter the generated files.

## Troubleshooting

- **No Wi-Fi/Bluetooth results:** inspect permission, location/Bluetooth state,
  adapter availability, and OS throttling in the capability center.
- **Windows local server is unreachable:** allow ProtoDeck through the firewall
  for the current network profile and listen on the LAN interface, not only localhost.
- **Linux Ping/Traceroute fails:** verify `ping`, `traceroute`, or `tracepath`
  installation and permissions; technical details are preserved.
- **SSH terminal works but files do not:** the host may lack SFTP. ProtoDeck
  attempts SCP/Shell browsing and explains when the target blocks all methods.
- **iPerf starts without data:** confirm role, target port, firewall, and peer
  version. Live raw output appears before the final structured statistics.
- **CJK renders as boxes:** distribute the complete desktop Bundle, not only
  the executable.

## Public documentation

- [Project home](../README_EN.md)
- [Architecture](../docs/architecture.md)
- [Platform support](../docs/platform-support.md)
- [Permissions and online services](../docs/permissions.md)
- [Privacy](../PRIVACY.md)
- [Third-party notices](../THIRD_PARTY_NOTICES.md)
- [Contributing](../CONTRIBUTING.md)
- [Security policy](../SECURITY.md)

ProtoDeck-owned code is licensed under the
[Apache License 2.0](../LICENSE). Third-party software and IEEE data retain
their respective licenses and terms.
