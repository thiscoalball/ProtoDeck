# ProtoDeck

面向网络工程师和开发者的本地优先网络工具箱。主要支持 Android、Windows 与 Linux；iOS
工程为实验性状态。各平台共享工具模型，同时保留真实的系统能力差异。

## 已接入

- 首页、Wi‑Fi、工具和远程四个主导航，浅色/深色主题、Riverpod、go_router 与 Drift/SQLite。
- Android/Windows/Linux 默认出口、本地 IPv4/IPv6、网关、DNS、MTU、Wi‑Fi 连接详情和附近 AP 快照。
- ICMPv4/v6、TCP、UDP Echo/Probe Ping；Traceroute；端口和局域网扫描；HTTP 诊断。
- 实时接口流量与活动端点、网络事件监视、Wi‑Fi 漫游分析、NTP、SNMP v2c/v3、Syslog 接收器和 PCAP/PCAPNG 离线解析。
- IPv4/IPv6 子网、地址分类、五类 IPv4/IPv6 互转、IPv6 格式化和数值表示。
- GeoIP 单条/批量查询和七日缓存。
- IEEE MA-L/MA-M/MA-S 离线 SQLite 数据库（53,413 条）、最长前缀查询、构建脚本、条件请求、完整校验、原子更新和恢复。
- SSH PTY 终端、主机密钥 TOFU、系统安全存储、SFTP/SCP/Shell 文件面板和 SSH 隧道。
- SFTP/SMB 浏览、上传、下载、新建、删除、重命名、chmod，以及目录优先的稳定排序。
- REST、WebSocket、SSE、MQTT、TCP/UDP、Telnet 和本地 HTTP/TCP 服务调试。
- Base64、URL、时间戳、正则、进制、位运算、文本 Diff、JSON/XML/YAML/SQL 格式化。
- 内置固定版本 iPerf 3.21，支持 Client/Server、实时终端输出、吞吐曲线和安全参数白名单；Linux/Windows 用户无需另行安装。

页面不会用假数据代替不可用能力。Android Wi‑Fi 扫描可能受权限和系统节流影响；Windows WLAN 页面明确标记系统缓存快照；UDP Probe 超时只能判定为未知。

桌面版内置 Apache-2.0 授权的 Droid Sans Fallback 作为 CJK 缺字回退，避免精简 Linux/Windows 环境因未安装中文字体而显示方框；拉丁文字仍使用平台默认 UI 字体。字体版权与完整许可证位于 `assets/fonts/DroidSansFallbackFull-LICENSE.txt`。

## 开发环境

安装 Flutter stable，并按照 `flutter doctor` 完成目标平台所需的工具链配置。Android 构建还
需要兼容的 JDK 与 Android SDK。

```bash
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
```

OUI 数据库更新（原始 CSV 只保存在项目生成目录，不打进 APK）：

```bash
dart run tool/oui/build_oui_database.dart
```

## SSH 服务器构建、PC 真机安装

服务器无法直接访问插在个人 PC 上的 USB 手机。在服务器构建后，把 APK 下载到 PC：

```text
build/app/outputs/flutter-apk/app-release.apk
```

然后在 PC 执行：

```bash
adb devices
adb install -r app-release.apk
```

热重载和断点调试需在 PC 安装 Flutter/Android SDK，并从 PC 执行 `flutter run`。iOS 构建需 macOS、Xcode 和 Apple 签名。

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
  -ReleaseDirectory build/windows/x64/runner/Release
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
- iPerf 3.21 与所需的 `cygwin1.dll` 随应用放在 Release 目录；仅当内置文件损坏时才回退查找 `PATH` 中的 `iperf3.exe`。CI 会校验固定版本归档的 SHA-256，并在 `licenses/source/` 附带对应 Cygwin 3.6.7-1 源码包和许可证。
- 首次启动 TCP/UDP、Syslog、iPerf Server 或本地测试服务时，可能需要允许 Windows Defender 防火墙访问对应网络。
- Windows BT/BLE 原生适配尚未完成，页面明确显示不可用，不生成模拟扫描结果。

仓库中的 `Build platform artifacts` 工作流支持在 Actions 页面手动勾选 Android、Linux、Windows；推送 `v*` 标签时会一次构建全部三端。Windows Runner 会上传 `ProtoDeck-windows-x64.zip`。Flutter 工具明确限制 Windows Desktop 只能在 Windows Host 构建，因此 Linux 主机不会生成伪造的 EXE。

## Linux 运行与构建

Ubuntu 22.04/24.04 或兼容的 Debian 系发行版需要 GTK3 与 Secret Service 开发库：

```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsecret-1-dev
flutter config --enable-linux-desktop
flutter pub get
flutter run -d linux
```

生成 Release Bundle：

```bash
flutter build linux --release --no-pub
tar -C build/linux/x64/release -czf build/ProtoDeck-linux-x64.tar.gz bundle
```

没有 sudo 权限的构建机可以使用仓库提供的引导脚本，把 Ubuntu 构建依赖放入未跟踪的本地
工具目录：

```bash
./tool/bootstrap_linux_build_deps.sh
./tool/build_linux_release_local.sh
```

运行 `bundle/nettools_mobile`。目标系统需要 GTK3、NetworkManager/iproute2；Ping 和 Traceroute 分别使用发行版中的 `iputils-ping` 与 `traceroute`/`tracepath`。iPerf 3.21 已静态编译并随 Bundle 提供。缺失外部工具时页面会显示具体错误，不会回退到模拟结果。

## 公共文档

- [项目首页](../README.md)
- [架构](../docs/architecture.md)
- [平台支持](../docs/platform-support.md)
- [权限与联网服务](../docs/permissions.md)
- [隐私说明](../PRIVACY.md)
- [第三方声明](../THIRD_PARTY_NOTICES.md)
