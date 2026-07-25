import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import 'api_realtime_workbench.dart';
import 'api_rest_workbench.dart';

class ApiWorkbenchPage extends StatefulWidget {
  const ApiWorkbenchPage({super.key});

  @override
  State<ApiWorkbenchPage> createState() => _ApiWorkbenchPageState();
}

class _ApiWorkbenchPageState extends State<ApiWorkbenchPage> {
  int _protocol = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('API 调试台')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: LocalizedText('REST')),
                ButtonSegment(value: 1, label: LocalizedText('WS')),
                ButtonSegment(value: 2, label: LocalizedText('SSE')),
                ButtonSegment(value: 3, label: LocalizedText('MQTT')),
              ],
              selected: {_protocol},
              onSelectionChanged: (value) =>
                  setState(() => _protocol = value.first),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: IndexedStack(
            index: _protocol,
            children: const [
              _WorkbenchScroll(child: ApiRestWorkbench()),
              _WorkbenchScroll(child: ApiRealtimeWorkbench(protocol: 1)),
              _WorkbenchScroll(child: ApiRealtimeWorkbench(protocol: 2)),
              _WorkbenchScroll(child: ApiRealtimeWorkbench(protocol: 3)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WorkbenchScroll extends StatelessWidget {
  const _WorkbenchScroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
    children: [child],
  );
}
