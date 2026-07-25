# ProtoDeck Flutter 应用

<p align="center">
  <strong>简体中文</strong> · <a href="README_EN.md">English</a>
</p>

本目录是 ProtoDeck 的 Flutter 应用源码，面向 Android、Windows 和 Linux 共用一套领域模型与
界面基础，并通过平台插件接入真实网络、Wi‑Fi、蓝牙、文件和流量能力。iOS 工程目前仅作为
实验性目标保留，不属于完整交付范围。

> 项目总览、截图和贡献入口请先阅读[仓库 README](../README.md)。本文侧重应用功能、代码结构、
> 平台边界、构建方式和开发约束。

## 功能目录

当前工具目录包含 65 个入口，按使用场景分为 9 类。部分功能依赖系统权限、外部命令或平台
原生接口，运行前会通过能力中心检测，不可用时展示原因和恢复建议，不以模拟结果冒充成功。

### Wi‑Fi

- **网络出口**：默认路由、活动接口、IPv4/IPv6、网关、DNS、MTU、VPN 和公网出口。
- **Wi‑Fi 分析**：当前连接、附近 AP、SSID/BSSID、RSSI、频段、信道、安全方式、信号历史、
  信道占用与推荐信道。
- **Wi‑Fi 漫游分析**：跟踪 BSSID 切换、RSSI、丢包、切换耗时和断流窗口。

### 网络诊断

- **一键网络医生**：按本地链路、网关、DNS 和互联网端点分层诊断，并给出状态解释。
- **网络事件监视**：记录默认路由、VPN、BSSID、DNS、网关和地址变化。
- **Ping**：ICMPv4/v6、TCP、UDP Echo、UDP Probe，支持次数、持续运行、间隔、超时、负载、
  协议版本、实时延迟曲线和统计摘要。
- **路由追踪**：逐跳延迟、地址、主机名、GeoIP 与按跳序绘制的地理路径。
- **DNS 查询**：A、AAAA、CNAME、MX、TXT、NS、PTR，自定义 DNS、DoT 和 DoH。
- **NTP 时间查询**：服务器时间、偏移、往返延迟、抖动、Stratum、根距离和时间源质量。
- **端口检测 / 局域网扫描**：单端口、列表、范围扫描以及在线主机发现和工具联动。
- **服务发现**：SSDP/UPnP、mDNS/Bonjour；另含 Wake-on-LAN、路径 MTU 和 STUN 映射。

### 流量与性能

- **实时流量监视**：接口上下行曲线、活动端点、协议分布；桌面端可关联 PID 和进程信息，
  并明确标记数据精度。
- **离线抓包分析**：读取 PCAP/PCAPNG，展示协议层级、I/O、端点和双向会话，不启用全局 VPN
  抓包。
- **iPerf3**：固定版本 Client/Server、TCP/UDP、IPv4/IPv6、反向、双向、并行流、码率、
  实时终端日志和吞吐曲线。命令输入仅解析白名单参数，不执行任意 Shell。

### 远程与服务

- **SSH**：密码/私钥认证、PTY、多会话、TOFU 主机指纹、ANSI 终端、快捷键和 Local/Remote/
  Dynamic SOCKS 隧道。同一应用进程内切换页面不会主动断开连接。
- **远程文件**：优先使用 SFTP；目标不提供 SFTP 子系统时可降级到 SCP/Shell 浏览。支持上传、
  下载、新建、删除、重命名、chmod、进度与名称/大小/时间稳定排序。
- **SMB**：SMB2/SMB3 共享、目录浏览与文件传输；Android 使用 SMBJ，Windows 使用系统 UNC，
  Linux 使用 libsmbclient。
- **协议与服务**：Telnet、TCP/UDP 调试助手、Syslog UDP/TCP 接收器、SNMP v2c/v3 浏览器、
  本地 HTTP/TCP Echo 服务。
- **蓝牙调试**：BLE 扫描、GATT 服务/特征浏览、读写和通知；经典蓝牙与服务端能力按平台门控。

### API 与协议

- **API 调试台**：REST 请求集合、参数、Header、Cookie、认证、Body、环境变量、响应断言与提取；
  同时提供 WebSocket 消息收发、SSE 事件流和 MQTT 订阅/发布。
- **HTTP 诊断**：状态码、耗时、响应头、正文类型识别；JSON、XML、HTML、文本和二进制使用不同
  展示方式。
- **协议辅助**：TLS 证书链与指纹、URL 编解码与解析、User-Agent 解析、HTTP 缓存/Cookie/
  CORS/安全响应头诊断。

### IP 与寻址

- IPv4/IPv6 子网边界、可用主机、广播地址、通配符掩码和 `/31`、`/32` 等边界规则。
- IPv4/IPv6 地址分类、映射/兼容/6to4/NAT64/IPv4-translatable 转换、IPv6 压缩展开、
  `ip6.arpa` 与数值表示。
- GeoIP 单条/批量查询、RDAP/ASN/BGP 归属、常用端口速查。
- IEEE MA-L、MA-M、MA-S 离线 OUI 数据库：MAC 查厂商、厂商反查前缀、最长前缀匹配和
  手动原子更新；另含 Linux/Windows/Cisco MAC 格式互转。

### 数据与转换

- Base64、二维码、时间戳/时区/批量转换、正则预设/捕获组/替换、2～36 进制、位运算。
- 文本 Diff、JSON/XML/YAML/SQL 格式化、Unicode、HTML 实体、Hexdump、Gzip。
- JSON/YAML/CSV 转换、JSONPath、JSON Schema/Diff/模型生成、大小端与整数查看。

### 安全与标识

- 文本或文件 Hash、HMAC 与结果逐项复制。
- JWT 解码和时间声明检查；UUID v4、ULID、安全密码生成。
- UUID、ULID、ObjectId、Snowflake 解析，以及 chmod 八进制/rwx 权限互转。

### 后端工程

- Cron 语义解析和未来执行时间。
- SQL 格式化、IN List 与 JSON 生成 INSERT。
- Semantic Version 校验、预发布版本与优先级比较。
- 日志分析：JSON Lines、日志级别、Trace ID 和 ANSI 清理。

## 核心体验与数据规则

- 一级导航为首页、Wi‑Fi、工具、远程；设置从首页进入，不显示独立“记录”导航。
- 手机采用紧凑卡片和底部导航；桌面采用分组侧栏、宽屏内容区和适配鼠标/键盘的交互。
- 非敏感表单通过 `ToolDraftRepository` 防抖保存，重新进入页面或重启应用可恢复上次输入、Tab、
  过滤和排序；运行中的 Ping、扫描、服务或抓包不会自动重启。
- 密码、Token、Cookie、私钥口令不会写入普通草稿。只有用户明确保存的凭据才进入平台安全存储。
- SSH/SMB 活跃会话在同一次运行内由会话注册表持有；应用重启后只恢复入口，不自动重连。
- 用户可见文本通过模块化本地化资源提供中英文；SSID、厂商名、协议样例和远端日志保持原文。
- 桌面版内置 Apache-2.0 授权的 Droid Sans Fallback 作为 CJK 缺字回退，完整许可证位于
  `assets/fonts/DroidSansFallbackFull-LICENSE.txt`。

## 架构与目录

```text
app/
├── android/                # Kotlin、权限、服务、Wi‑Fi/蜂窝/蓝牙/SMB 原生接入
├── ios/                    # 实验性 iOS Runner
├── linux/                  # GTK、BlueZ、libsmbclient 与桌面系统接口
├── windows/                # Win32/WinRT、WLAN、蓝牙、UNC 与网络接口
├── assets/                 # 字体、内置数据和许可证资源
├── lib/
│   ├── core/               # 主题、路由、通用组件、能力与任务基础设施
│   ├── data/               # Drift、Repository、Provider、缓存和安全存储
│   ├── models/             # 跨平台领域模型和结构化失败类型
│   ├── services/           # 网络、远程、解析、转换和任务服务
│   ├── state/              # Riverpod Provider、会话注册表与应用状态
│   ├── ui/                 # 首页、工具目录、远程和设置页面
│   └── l10n/               # 按业务模块拆分的中英文资源
├── test/                   # 单元、Widget、本地化与回归测试
└── tool/                   # OUI、截图、桌面依赖和打包脚本
```

主要技术组件：

- Flutter / Dart 负责跨平台 UI、DNS、SSH/SFTP、API 调试、IP 计算与离线开发工具。
- Riverpod 管理依赖和状态，go_router 管理导航，Drift/SQLite 管理草稿、缓存和结构化数据。
- Android 使用 Kotlin 平台插件；Windows 使用 C++/WinRT/Win32；Linux 使用 GTK、D-Bus/BlueZ、
  libsmbclient 与 `/proc`/系统命令。
- 长任务统一采用空闲、校验、运行、停止、完成、失败和中断状态，并要求实现取消与资源释放。
- 平台调用返回结构化错误码和技术详情，用户文案在 Flutter 层本地化；禁止原生层拼接固定中文提示。

更多设计背景见[架构文档](../docs/architecture.md)和[平台支持矩阵](../docs/platform-support.md)。

## 平台能力矩阵

| 能力 | Android 10+ | Windows 10/11 x64 | Ubuntu 22.04/24.04 | iOS |
|---|---|---|---|---|
| 当前网络/路由/DNS | 原生 | 系统接口 | NetworkManager/iproute2 | 实验性 |
| Wi‑Fi 当前连接/扫描 | 原生，受权限和节流限制 | WLAN API，部分为系统缓存 | NetworkManager/iw | 实验性 |
| BLE | 扫描、GATT Client/Server | WinRT 扫描与 GATT Client | BlueZ 扫描与 GATT Client | 实验性 |
| 经典蓝牙/RFCOMM | 支持，受系统权限限制 | 当前不可用 | 依赖 BlueZ，部分可用 | 实验性 |
| SMB | SMBJ | UNC/系统凭据 | libsmbclient | 未承诺 |
| 进程流量归属 | Android UID/应用信息 | PID/活动端点 | PID/socket 关联 | 未承诺 |
| SSH/SFTP/API/IP 工具 | 支持 | 支持 | 支持 | 实验性 |
| iPerf3 | 随应用接入 | 随 Bundle 打包 | 随 Bundle 打包 | 未承诺 |

入口不会因为平台不支持而消失；能力中心会标记“可用、部分可用、需要权限、需要依赖、需要提权
或当前平台不支持”，并提供重新检测、打开设置或依赖安装建议。

## 开发环境

CI 当前固定使用 Flutter 3.44.8。开发机可使用兼容的 Flutter stable，但提交前应以工作流版本
完成分析和测试。进入本目录后执行：

```bash
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

推荐的提交前检查：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

涉及网络和设备的功能需要在真机或目标桌面系统验证。单元测试通过并不代表 Wi‑Fi 扫描、蓝牙、
防火墙、系统凭据或平台命令已在目标环境可用。

## Android 运行与构建

Android 最低版本为 Android 10/API 29。需要 JDK 17、Android SDK 和接受过许可证的构建工具：

```bash
flutter doctor
flutter pub get
flutter build apk --release --no-pub
```

Release APK 位于：

```text
build/app/outputs/flutter-apk/app-release.apk
```

真机调试常见权限包括附近 Wi‑Fi、位置服务、附近设备/蓝牙、通知和前台服务。具体用途、系统
版本差异和拒绝后的行为见[权限说明](../docs/permissions.md)。Android Wi‑Fi 主动扫描受系统节流
限制；页面必须显示结果采集时间，不能把缓存结果标成实时扫描。

### SSH 构建机与 PC 真机安装

服务器无法直接访问插在个人 PC 上的 USB 手机。在服务器构建后，把 APK 下载到 PC：

```text
build/app/outputs/flutter-apk/app-release.apk
```

然后在 PC 执行：

```bash
adb devices
adb install -r app-release.apk
```

热重载和断点调试需在连接手机的 PC 安装 Flutter/Android SDK，并从该 PC 执行
`flutter run -d <device-id>`。服务器只负责编译时无需安装 ADB 设备驱动。

## Windows 运行与构建

Windows 10/11 上安装 Flutter，并通过 Visual Studio Installer 安装“使用 C++ 的桌面开发”（含 MSVC、CMake 和 Windows SDK），然后执行：

```powershell
flutter config --enable-windows-desktop
flutter doctor
flutter pub get
flutter run -d windows
```

生成 Release 目录：

```powershell
flutter build windows --release
./tool/build_bundled_iperf_windows.ps1 `
  -OutputDirectory build/windows/x64/runner/Release
Compress-Archive `
  -Path build/windows/x64/runner/Release/* `
  -DestinationPath build/ProtoDeck-windows-x64.zip `
  -Force
```

产物位于 `build/ProtoDeck-windows-x64.zip`。分发时需要保留压缩包内的整个 Release 目录内容，不能只复制主程序 EXE。

Windows 平台说明：

- 当前网络、DNS、网关、地址、Wi‑Fi、Ping、Traceroute、路径 MTU、实时接口流量和活动 TCP/UDP 端点读取 Windows 系统真实数据。
- SSH/SFTP、API、Socket、DNS、NTP、SNMP、Syslog、PCAP、编码和 IP 工具直接复用跨平台实现。
- SMB 使用 Windows UNC 与系统凭据管理器，不把密码拼接到命令行。
- 蓝牙使用 WinRT 提供 BLE 扫描、设备详情和 GATT Client；经典蓝牙/RFCOMM 当前明确标记不可用。
- 多网卡页面区分以太网、Wi‑Fi、虚拟网卡和 VPN。以太网展示连接速率而不是虚构信号强度。
- iPerf 3.21 与所需的 `cygwin1.dll` 随应用放在 Release 目录；仅当内置文件损坏时才回退查找 `PATH` 中的 `iperf3.exe`。CI 会校验固定版本归档的 SHA-256，并在 `licenses/source/` 附带对应 Cygwin 3.6.7-1 源码包和许可证。
- 首次启动 TCP/UDP、Syslog、iPerf Server 或本地测试服务时，可能需要允许 Windows Defender 防火墙访问对应网络。
- 文件下载使用桌面目录选择器；SSH 终端需要保持焦点、键盘输入、粘贴和 ANSI 控制序列可用。

Flutter 工具明确限制 Windows Desktop 只能在 Windows Host 构建，因此 Linux 主机不会生成伪造的 EXE。

## Linux 运行与构建

Ubuntu 22.04/24.04 或兼容的 Debian 系发行版需要 GTK3 与 Secret Service 开发库：

```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libsecret-1-dev libsmbclient-dev libbluetooth-dev bluez
flutter config --enable-linux-desktop
flutter pub get
flutter run -d linux
```

生成 Release Bundle：

```bash
./tool/build_linux_release_local.sh
```

没有 sudo 权限的构建机可以使用仓库提供的引导脚本，把 Ubuntu 构建依赖放入未跟踪的本地
工具目录：

```bash
./tool/bootstrap_linux_build_deps.sh
./tool/build_linux_release_local.sh
```

解压后运行 Bundle 中的可执行文件。目标系统需要 GTK3、BlueZ、libsmbclient、
NetworkManager/iproute2；Ping 和 Traceroute 分别使用发行版中的 `iputils-ping` 与
`traceroute`/`tracepath`。iPerf 3.21 已静态编译并随 Bundle 提供。缺少 BlueZ 服务、蓝牙
适配器、libsmbclient 或外部命令时，能力中心会显示具体原因，不会回退到模拟结果。

Linux 平台说明：

- BLE 通过 BlueZ D-Bus 扫描并提供 GATT Client；RFCOMM 和 GATT Server 取决于系统服务、
  内核与权限，当前属于部分可用能力。
- SMB 使用 libsmbclient，凭据通过参数/安全存储传递，不出现在命令行或普通日志。
- 普通流量模式通过 `/proc/net` 和进程文件描述符关联 Socket；接口总字节与进程归属是不同
  精度的数据，UI 不应把两者混为精确的应用字节数。
- 精简桌面若缺少 CJK 字体，会使用随应用提供的回退字体。

## 版本、构建渠道与 GitHub Actions

设置页“关于 ProtoDeck”读取统一 BuildInfo，展示语义版本、构建号、渠道、Git 短提交号、平台
和架构。版本注入规则如下：

| 触发方式 | Flutter 编译模式 | 应用渠道 | 版本来源 | 平台 |
|---|---|---|---|---|
| 推送 `v0.0.1` Tag | Release | `Release` | Tag 中的 `0.0.1` | Android、Linux、Windows |
| Actions 手动触发 | Release | `Debug` | 手动输入或 `pubspec.yaml` | 可勾选平台 |
| 本地测试固件 | Release | `Debug` | 命令行 `--build-name` | 当前主机支持的平台 |
| `flutter run` | Debug/Profile | `Debug` | `pubspec.yaml` | 当前设备 |

“Debug”渠道表示内部测试身份，不代表手动 Actions 产物使用 Flutter Debug 编译；可分发固件仍使用
Release 优化。正式发布 Tag：

```bash
git tag v0.0.1
git push origin v0.0.1
```

本地生成带 Debug 渠道标识的 Release 优化固件：

```bash
# Android / Linux
flutter build apk --release --no-pub \
  --build-name 0.0.1 --build-number 1 \
  --dart-define BUILD_CHANNEL=debug --dart-define GIT_SHA=local

flutter build linux --release --no-pub \
  --build-name 0.0.1 --build-number 1 \
  --dart-define BUILD_CHANNEL=debug --dart-define GIT_SHA=local
```

Windows PowerShell：

```powershell
flutter build windows --release --no-pub `
  --build-name 0.0.1 --build-number 1 `
  --dart-define BUILD_CHANNEL=debug --dart-define GIT_SHA=local
```

GitHub 的 **Build platform artifacts** 工作流在 Actions 页面支持手动选择平台。Tag 构建强制
生成三端产物。每个产物附带 `.sha256`，默认保留 14 天；它们位于对应工作流运行的
**Artifacts** 区域，并不会自动创建 GitHub Release 页面。

## OUI 离线数据库

应用只打包生成后的 SQLite 数据库，不打包原始 CSV。构建脚本从 IEEE 官方源处理 MA-L、MA-M
和 MA-S，校验表头、Registry、前缀长度、十六进制格式、记录数量变化与 SHA-256，并执行
SQLite 完整性检查：

```bash
dart run tool/oui/build_oui_database.dart
```

运行时更新由用户在设置页手动触发：下载到应用私有 staging 目录，通过同样的完整校验和抽样
查询后生成 next 数据库，再在同一文件系统原子替换。失败时保留当前数据库，并可恢复随应用
内置的版本。

## 测试与质量门禁

至少覆盖以下高风险路径：

- IPv4/IPv6 边界、BigInt 数量、地址分类、通配符和五类转换。
- OUI 三种前缀长度、最长前缀匹配、CSV 截断/错误表头、更新取消、原子替换和回滚。
- Ping/iPerf/扫描的取消、后台、超时、重复运行和资源释放。
- Wi‑Fi/蓝牙权限拒绝、系统节流、缺少适配器、缺少服务和平台降级。
- SSH 指纹变化、私钥、ANSI 输入、活跃会话切换，以及 SFTP/SCP/Shell 文件降级。
- SMB 中文文件名、大文件、排序、冲突、取消和断线恢复。
- API 草稿、WebSocket/MQTT 消息历史、JSON/XML/HTML 响应展示和敏感字段过滤。
- 中英文翻译键/参数一致性，以及英文页面可见文本残留中文检测。

基础质量命令：

```bash
flutter analyze --no-pub
flutter test --no-pub
git diff --check
```

平台功能应在对应系统上验证。Linux 主机不能代替 Windows 原生构建与 WinRT 行为测试；桌面
构建通过也不能代替 Android 真机权限和后台任务测试。

## 文档截图

仓库截图由脚本从可复现的 Flutter Widget 场景生成，避免依赖维护者逐页手工截图：

```bash
./tool/generate_docs_screenshots.sh
```

输出位于 `../docs/screenshots/`。更新界面后若截图发生变化，应一并检查文字溢出、平台尺寸和
中英文布局，再提交新图片。

## 常见排障

- **附近 Wi‑Fi/蓝牙无结果**：先查看能力中心的权限、位置/蓝牙开关、适配器和系统节流状态；
  “扫描正在运行”不等于设备一定广播可发现数据。
- **Windows 本地服务无法被访问**：确认系统防火墙已允许 ProtoDeck 所在网络类型，并检查监听
  地址是否为局域网接口而不是仅 `127.0.0.1`。
- **Linux Ping/Traceroute 失败**：检查 `ping`、`traceroute` 或 `tracepath` 是否安装以及权限；
  应用会优先展示原始技术详情。
- **SSH 有终端但没有文件列表**：目标可能未启用 SFTP；应用会尝试 SCP/Shell 兼容路径。若目标
  同时限制这些能力，终端仍可用，但文件面板会明确说明失败原因。
- **iPerf 启动后没有数据**：确认 Client/Server 角色、目标端口、防火墙和对端版本；页面显示实时
  原始输出，最终 JSON 仅用于结构化统计。
- **中文显示方框**：确认 Bundle 资源完整，不能只复制桌面主程序可执行文件。

## 公共文档

- [项目首页](../README.md)
- [架构](../docs/architecture.md)
- [平台支持](../docs/platform-support.md)
- [权限与联网服务](../docs/permissions.md)
- [隐私说明](../PRIVACY.md)
- [第三方声明](../THIRD_PARTY_NOTICES.md)
- [贡献指南](../CONTRIBUTING.md)
- [安全策略](../SECURITY.md)

ProtoDeck 自有代码采用 [Apache License 2.0](../LICENSE)。第三方组件和 IEEE 数据继续遵循各自
许可证与使用条款。
