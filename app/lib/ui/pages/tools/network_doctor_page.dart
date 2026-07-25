import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/network_doctor_service.dart';
import '../../../models/tool_route_args.dart';
import '../../../state/app_state.dart';
import '../../tool_launcher.dart';

class NetworkDoctorPage extends StatefulWidget {
  const NetworkDoctorPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<NetworkDoctorPage> createState() => _NetworkDoctorPageState();
}

class _NetworkDoctorPageState extends State<NetworkDoctorPage> {
  NetworkDoctorProgress? _progress;
  NetworkDoctorCancellationToken? _token;
  StreamSubscription<NetworkDoctorProgress>? _subscription;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _token?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('一键网络医生'),
        actions: [
          if (progress?.steps.isNotEmpty == true)
            IconButton(
              onPressed: _copyReport,
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: context.tr('复制诊断报告'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.health_and_safety_outlined, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LocalizedText(
                        progress?.conclusion ?? progress?.current ?? '准备诊断',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                if (progress?.running == true) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final step in progress?.steps ?? const <DoctorStepResult>[])
            _stepCard(step),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: progress?.running == true ? null : _start,
                  icon: const Icon(Icons.refresh),
                  label: const LocalizedText('重新诊断'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: progress?.running == true ? _stop : null,
                icon: const Icon(Icons.stop),
                label: const LocalizedText('停止'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepCard(DoctorStepResult step) {
    final (icon, color) = switch (step.status) {
      DoctorStepStatus.passed => (Icons.check_circle, const Color(0xFF168A5B)),
      DoctorStepStatus.warning => (
        Icons.warning_amber,
        const Color(0xFFCA7A16),
      ),
      DoctorStepStatus.failed => (Icons.cancel, const Color(0xFFD34D4D)),
    };
    final target = _deeperTool(step);
    return Card(
      child: ListTile(
        onTap: target == null
            ? null
            : () => openTool(
                context,
                target.$1,
                widget.appState,
                args: target.$2,
              ),
        leading: Icon(icon, color: color),
        title: LocalizedText(
          step.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalizedText(step.detail),
            Text(
              target == null
                  ? '${step.elapsed.inMilliseconds} ms'
                  : '${step.elapsed.inMilliseconds} ms · ${context.tr('点击深入排查')}',
            ),
          ],
        ),
        isThreeLine: true,
        trailing: target == null
            ? null
            : const Icon(Icons.arrow_outward_rounded),
      ),
    );
  }

  (String, ToolRouteArgs?)? _deeperTool(DoctorStepResult step) =>
      switch (step.id) {
        'interface' => ('network', null),
        'signal' => ('wifi', null),
        'gateway' => (
          'ping',
          ToolRouteArgs(
            target: RegExp(
              r'(?:(?:\d{1,3}\.){3}\d{1,3}|[0-9a-fA-F:]{2,})',
            ).firstMatch(step.detail)?.group(0),
            sourceToolId: 'doctor',
          ),
        ),
        'dns' => (
          'dns',
          const ToolRouteArgs(target: 'baidu.com', sourceToolId: 'doctor'),
        ),
        'dual_stack' => ('ip_tools', null),
        'internet' => (
          'http',
          const ToolRouteArgs(
            url: 'https://www.baidu.com/',
            sourceToolId: 'doctor',
          ),
        ),
        _ => null,
      };

  Future<void> _copyReport() async {
    final progress = _progress;
    if (progress == null) return;
    final report = StringBuffer()
      ..writeln('ProtoDeck Network Doctor')
      ..writeln(progress.conclusion ?? progress.current);
    for (final step in progress.steps) {
      report
        ..writeln()
        ..writeln('[${step.status.name.toUpperCase()}] ${step.title}')
        ..writeln('${step.detail} · ${step.elapsed.inMilliseconds} ms');
    }
    await Clipboard.setData(ClipboardData(text: report.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: LocalizedText('诊断报告已复制')));
  }

  void _start() {
    _subscription?.cancel();
    final token = NetworkDoctorCancellationToken();
    _token = token;
    setState(() => _progress = null);
    _subscription = NetworkDoctorService().run(token: token).listen((progress) {
      if (mounted) setState(() => _progress = progress);
    });
  }

  void _stop() {
    _token?.cancel();
    setState(() {
      final current = _progress;
      if (current != null) {
        _progress = NetworkDoctorProgress(
          steps: current.steps,
          running: false,
          current: '',
          conclusion: '诊断已停止',
        );
      }
    });
  }
}
