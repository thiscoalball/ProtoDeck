import 'dart:io';

import '../models/network_context.dart';
import 'dns_service.dart';
import 'icmp_ping_service.dart';
import 'native_network_service.dart';

enum DoctorStepStatus { passed, warning, failed }

class DoctorStepResult {
  const DoctorStepResult({
    required this.id,
    required this.title,
    required this.status,
    required this.detail,
    required this.elapsed,
  });

  final String id;
  final String title;
  final DoctorStepStatus status;
  final String detail;
  final Duration elapsed;
}

class NetworkDoctorProgress {
  const NetworkDoctorProgress({
    required this.steps,
    required this.running,
    required this.current,
    this.conclusion,
  });

  final List<DoctorStepResult> steps;
  final bool running;
  final String current;
  final String? conclusion;
}

class NetworkDoctorCancellationToken {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class NetworkDoctorService {
  NetworkDoctorService({NativeNetworkService? native})
    : _native = native ?? NativeNetworkService();

  final NativeNetworkService _native;

  Stream<NetworkDoctorProgress> run({
    required NetworkDoctorCancellationToken token,
  }) async* {
    final steps = <DoctorStepResult>[];
    NetworkContext context;
    yield NetworkDoctorProgress(
      steps: List.unmodifiable(steps),
      running: true,
      current: '读取当前网络',
    );
    final interfaceWatch = Stopwatch()..start();
    try {
      context = await _native.getNetworkContext();
      interfaceWatch.stop();
      steps.add(
        DoctorStepResult(
          id: 'interface',
          title: '本机网络',
          status: context.connected
              ? DoctorStepStatus.passed
              : DoctorStepStatus.failed,
          detail: context.connected
              ? '${context.transports.join(' / ').toUpperCase()} · ${context.interfaceName ?? '接口未知'}'
              : '没有活动网络，请先连接 Wi‑Fi、蜂窝或以太网',
          elapsed: interfaceWatch.elapsed,
        ),
      );
    } on Object catch (error) {
      interfaceWatch.stop();
      steps.add(
        DoctorStepResult(
          id: 'interface',
          title: '本机网络',
          status: DoctorStepStatus.failed,
          detail: '读取失败：$error',
          elapsed: interfaceWatch.elapsed,
        ),
      );
      yield NetworkDoctorProgress(
        steps: List.unmodifiable(steps),
        running: false,
        current: '',
        conclusion: '无法读取本机网络，诊断已停止',
      );
      return;
    }
    if (!context.connected || token.cancelled) {
      yield NetworkDoctorProgress(
        steps: List.unmodifiable(steps),
        running: false,
        current: '',
        conclusion: token.cancelled ? '诊断已停止' : '当前没有可诊断的活动网络',
      );
      return;
    }
    yield NetworkDoctorProgress(
      steps: List.unmodifiable(steps),
      running: true,
      current: '评估无线信号',
    );

    final signalWatch = Stopwatch()..start();
    final signal = _signal(context);
    signalWatch.stop();
    steps.add(
      DoctorStepResult(
        id: 'signal',
        title: '接入信号',
        status: signal.$1,
        detail: signal.$2,
        elapsed: signalWatch.elapsed,
      ),
    );
    if (token.cancelled) return;
    yield NetworkDoctorProgress(
      steps: List.unmodifiable(steps),
      running: true,
      current: '检测默认网关',
    );

    final gateways = [...context.gateways, ...context.lanGateways];
    final gateway = gateways.where((value) => value.isNotEmpty).firstOrNull;
    final gatewayWatch = Stopwatch()..start();
    if (gateway == null) {
      gatewayWatch.stop();
      steps.add(
        DoctorStepResult(
          id: 'gateway',
          title: '默认网关',
          status: DoctorStepStatus.warning,
          detail: '系统没有提供默认网关，VPN 或部分蜂窝网络可能出现此情况',
          elapsed: gatewayWatch.elapsed,
        ),
      );
    } else {
      try {
        final ping = await IcmpPingService(
          native: _native,
        ).run(host: gateway, count: 3, timeoutMs: 1200, intervalMs: 250);
        gatewayWatch.stop();
        steps.add(
          DoctorStepResult(
            id: 'gateway',
            title: '默认网关',
            status: ping.received > 0
                ? DoctorStepStatus.passed
                : DoctorStepStatus.warning,
            detail: ping.received > 0
                ? '$gateway · ${ping.average?.toStringAsFixed(1) ?? '—'} ms · 丢包 ${ping.lossPercent.toStringAsFixed(0)}%'
                : '$gateway 未响应 ICMP；网关可能禁用了 Ping，不等同于断网',
            elapsed: gatewayWatch.elapsed,
          ),
        );
      } on Object catch (error) {
        gatewayWatch.stop();
        steps.add(
          DoctorStepResult(
            id: 'gateway',
            title: '默认网关',
            status: DoctorStepStatus.warning,
            detail: '$gateway 探测受限：$error',
            elapsed: gatewayWatch.elapsed,
          ),
        );
      }
    }
    if (token.cancelled) return;
    yield NetworkDoctorProgress(
      steps: List.unmodifiable(steps),
      running: true,
      current: '检测 DNS 解析',
    );

    final dns = await DnsService().lookup(
      'baidu.com',
      type: DnsRecordType.a,
      transport: DnsTransport.udp,
      server: '223.5.5.5',
      timeout: const Duration(seconds: 5),
    );
    steps.add(
      DoctorStepResult(
        id: 'dns',
        title: 'DNS 解析',
        status: dns.success && dns.records.isNotEmpty
            ? DoctorStepStatus.passed
            : DoctorStepStatus.failed,
        detail: dns.success && dns.records.isNotEmpty
            ? '223.5.5.5 · ${dns.records.first.data} · ${dns.elapsed.inMilliseconds} ms'
            : dns.error ?? '没有返回 A 记录',
        elapsed: dns.elapsed,
      ),
    );
    if (token.cancelled) return;
    yield NetworkDoctorProgress(
      steps: List.unmodifiable(steps),
      running: true,
      current: '检查 IPv4/IPv6',
    );

    final stackWatch = Stopwatch()..start();
    final hasV4 = context.addresses.any((address) => address.family == 'IPv4');
    final hasV6 = context.addresses.any(
      (address) =>
          address.family == 'IPv6' && !address.address.startsWith('fe80:'),
    );
    stackWatch.stop();
    steps.add(
      DoctorStepResult(
        id: 'dual_stack',
        title: 'IP 协议栈',
        status: hasV4 || hasV6
            ? DoctorStepStatus.passed
            : DoctorStepStatus.failed,
        detail:
            '${hasV4 ? 'IPv4 可用' : '无 IPv4'} · ${hasV6 ? 'IPv6 可用' : '无全局 IPv6'}',
        elapsed: stackWatch.elapsed,
      ),
    );
    if (token.cancelled) return;
    yield NetworkDoctorProgress(
      steps: List.unmodifiable(steps),
      running: true,
      current: '检测互联网与认证门户',
    );

    final internet = await _internetCheck(context);
    steps.add(internet);
    final failures = steps
        .where((step) => step.status == DoctorStepStatus.failed)
        .length;
    final warnings = steps
        .where((step) => step.status == DoctorStepStatus.warning)
        .length;
    final conclusion = failures > 0
        ? '发现 $failures 项故障${warnings > 0 ? '、$warnings 项提醒' : ''}，请优先处理红色项目'
        : warnings > 0
        ? '网络基本可用，有 $warnings 项需要关注'
        : '无线、局域网、DNS 和互联网检查均正常';
    yield NetworkDoctorProgress(
      steps: List.unmodifiable(steps),
      running: false,
      current: '',
      conclusion: conclusion,
    );
  }

  (DoctorStepStatus, String) _signal(NetworkContext context) {
    final wifi = context.wifi;
    if (context.transports.contains('wifi') && wifi?.rssi != null) {
      final rssi = wifi!.rssi!;
      final status = rssi >= -75
          ? DoctorStepStatus.passed
          : rssi >= -85
          ? DoctorStepStatus.warning
          : DoctorStepStatus.failed;
      return (status, 'Wi‑Fi RSSI $rssi dBm · CH ${wifi.channel ?? '—'}');
    }
    final cellular = context.cellular;
    if (context.transports.contains('cellular') && cellular != null) {
      final value =
          cellular.metrics['SS-RSRP'] ??
          cellular.metrics['RSRP'] ??
          cellular.metrics['CSI-RSRP'] ??
          cellular.dbm;
      if (value == null) {
        return (
          DoctorStepStatus.warning,
          '${cellular.radioTechnology ?? '蜂窝'} · 系统未提供信号指标',
        );
      }
      final status = value >= -100
          ? DoctorStepStatus.passed
          : value >= -110
          ? DoctorStepStatus.warning
          : DoctorStepStatus.failed;
      return (status, '${cellular.radioTechnology ?? '蜂窝'} · $value dBm');
    }
    return (DoctorStepStatus.passed, '当前为有线或 VPN 接入，无需评估无线信号');
  }

  Future<DoctorStepResult> _internetCheck(NetworkContext context) async {
    final watch = Stopwatch()..start();
    if (context.captivePortal) {
      watch.stop();
      return DoctorStepResult(
        id: 'internet',
        title: '互联网访问',
        status: DoctorStepStatus.failed,
        detail: '${Platform.operatingSystem} 检测到认证门户，请先完成网络登录',
        elapsed: watch.elapsed,
      );
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(
        Uri.parse('http://connect.rom.miui.com/generate_204'),
      );
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      await response.drain<void>();
      watch.stop();
      if (response.statusCode == 204) {
        return DoctorStepResult(
          id: 'internet',
          title: '互联网访问',
          status: DoctorStepStatus.passed,
          detail: 'HTTP 204 探测成功 · ${watch.elapsedMilliseconds} ms',
          elapsed: watch.elapsed,
        );
      }
      final redirected =
          response.isRedirect ||
          response.statusCode == 200 ||
          response.statusCode == 511;
      return DoctorStepResult(
        id: 'internet',
        title: '互联网访问',
        status: redirected ? DoctorStepStatus.warning : DoctorStepStatus.failed,
        detail: redirected
            ? '返回 HTTP ${response.statusCode}，可能存在认证门户或透明代理'
            : '探测返回 HTTP ${response.statusCode}',
        elapsed: watch.elapsed,
      );
    } on Object catch (error) {
      watch.stop();
      return DoctorStepResult(
        id: 'internet',
        title: '互联网访问',
        status: context.validated
            ? DoctorStepStatus.warning
            : DoctorStepStatus.failed,
        detail: context.validated
            ? '系统报告互联网可用，但探测端点访问失败：$error'
            : '互联网未验证：$error',
        elapsed: watch.elapsed,
      );
    } finally {
      client.close(force: true);
    }
  }
}

extension _FirstOrNullDoctor<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
