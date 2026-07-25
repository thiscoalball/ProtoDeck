import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/network_doctor_service.dart';

class NetworkDoctorPage extends StatefulWidget {
  const NetworkDoctorPage({super.key});

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
      appBar: AppBar(title: const LocalizedText('一键网络医生')),
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
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: LocalizedText(
          step.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: LocalizedText(step.detail),
        trailing: LocalizedText('${step.elapsed.inMilliseconds}ms'),
      ),
    );
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
