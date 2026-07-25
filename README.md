# ProtoDeck

ProtoDeck 是一款面向网络工程师、开发者和设备调试人员的本地优先的开发工具箱。它使用
Flutter 构建，在 Android、Windows 与 Linux 上提供一致的工具模型，并针对移动端和桌面端
分别优化交互布局。

> 项目仍在积极开发。诊断结果取决于操作系统权限、网络环境和外部服务可用性；不可用能力
> 会明确显示原因，不会使用模拟数据替代真实结果。

## 主要能力

- 网络状态、Wi-Fi 分析、信号历史、信道占用和网络事件监视
- ICMP/TCP/UDP Ping、Traceroute、DNS、NTP、端口与局域网扫描
- iPerf 3、HTTP、本地 HTTP/TCP 服务、Syslog、SNMP、PCAP 离线分析
- IPv4/IPv6、子网、通配符掩码、MAC/OUI、GeoIP 和地址格式转换
- SSH 终端、SFTP/SCP/Shell 文件浏览、SSH 隧道和 SMB
- REST、WebSocket、SSE、MQTT、TCP/UDP、Telnet 与蓝牙调试
- Base64、URL、时间戳、正则、Hash/HMAC、进制、Diff 和结构化数据格式化

更完整的功能说明见 [应用文档](app/README.md)。

## 平台状态

| 平台 | 状态 | 说明 |
|---|---|---|
| Android 10+ | 主要支持平台 | Wi-Fi、蜂窝、蓝牙及系统网络能力以真机权限为准 |
| Windows 10/11 x64 | 支持 | 原生网络接口、Wi-Fi、桌面 SSH/文件操作；BT/BLE 尚未接入 |
| Ubuntu 22.04/24.04 x64 | 支持 | 需要 GTK3；部分诊断依赖发行版网络工具 |
| iOS | 实验性 | 工程骨架存在，但尚未承诺与 Android 等价的功能覆盖 |

详细矩阵见 [平台支持](docs/platform-support.md)。

## 快速开始

先安装 [Flutter stable](https://docs.flutter.dev/get-started/install)，并按照目标平台完成
`flutter doctor` 所提示的工具链配置。

```bash
git clone https://github.com/thiscoalball/ProtoDeck.git
cd ProtoDeck/app
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Android Release 构建：

```bash
flutter build apk --release --no-pub
```

Windows 与 Linux 的依赖、内置 iPerf 打包和运行方式见
[应用构建说明](app/README.md)。CI 也支持手动选择平台构建；推送 `v*` 标签时会构建
Android、Windows 和 Linux 三个平台的产物。

## 权限、隐私与安全

ProtoDeck 不内置广告、用户行为分析或遥测 SDK。网络诊断可能把用户输入的目标、当前公网
地址或域名发送到用户选择的服务器和项目文档列出的在线 Provider。SSH/API 等凭据使用平台
安全存储；工作区、会话和缓存默认保存在本机。

- [隐私说明](PRIVACY.md)
- [权限与联网服务](docs/permissions.md)
- [安全漏洞报告](SECURITY.md)

请只扫描、连接或测试你拥有或明确获准管理的设备与网络。

## 项目结构

```text
app/               Flutter 应用与平台工程
docs/              架构、平台和权限文档
.github/           CI、Issue 与 PR 模板
```

架构概览见 [docs/architecture.md](docs/architecture.md)。

## 参与贡献

提交变更前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。Bug 与功能建议请使用仓库的结构化 Issue 模板；
安全问题请勿创建公开 Issue。

## 第三方组件与数据

项目包含或调用 iPerf、Cygwin、Droid Sans Fallback、SMBJ、IEEE Registration Authority
公开列表及若干 Flutter/Dart 依赖。完整来源和许可证入口见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可证

ProtoDeck 自有代码以 [Apache License 2.0](LICENSE) 开源。第三方组件和数据继续遵循各自的
许可证及使用条款。
