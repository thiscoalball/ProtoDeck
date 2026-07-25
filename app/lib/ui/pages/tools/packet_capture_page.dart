import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../models/structured_payload.dart';
import '../../../services/pcap_analysis_service.dart';
import '../../widgets/structured_data_viewer.dart';

class PacketCapturePage extends StatefulWidget {
  const PacketCapturePage({super.key});

  @override
  State<PacketCapturePage> createState() => _PacketCapturePageState();
}

class _PacketCapturePageState extends State<PacketCapturePage> {
  final _service = PcapAnalysisService();
  CaptureAnalysis? _analysis;
  bool _running = false;
  double _progress = 0;
  String? _error;
  String _query = '';
  String _protocol = '全部';

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('离线抓包分析')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            _IntroCard(onPick: _running ? null : _pickFile),
            if (_running) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const LocalizedText(
                        '正在解析数据包',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _progress == 0 ? null : _progress,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _service.cancel,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const LocalizedText('停止解析'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline_rounded),
                  title: const LocalizedText('无法解析抓包文件'),
                  subtitle: LocalizedText(error),
                ),
              ),
            ],
            if (analysis != null) ...[
              const SizedBox(height: 18),
              _CaptureSummary(analysis: analysis),
              const SizedBox(height: 18),
              _ProtocolOverview(analysis: analysis),
              const SizedBox(height: 18),
              _buildPackets(analysis),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPackets(CaptureAnalysis analysis) {
    final protocols = ['全部', ...analysis.protocolBytes.keys.toList()..sort()];
    final query = _query.trim().toLowerCase();
    final packets = analysis.packets
        .where((packet) {
          if (_protocol != '全部' && packet.protocol != _protocol) return false;
          return query.isEmpty ||
              packet.summary.toLowerCase().contains(query) ||
              packet.source.toLowerCase().contains(query) ||
              packet.destination.toLowerCase().contains(query);
        })
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LocalizedText(
          '数据包',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hint: LocalizedText('过滤协议、IP、端口或摘要'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: protocols.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final value = protocols[index];
              return ChoiceChip(
                label: LocalizedText(value),
                selected: _protocol == value,
                showCheckmark: false,
                onSelected: (_) => setState(() => _protocol = value),
              );
            },
          ),
        ),
        if (analysis.truncatedPacketList)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LocalizedText(
              '文件共有 ${analysis.packetCount} 个包，列表保留前 ${analysis.packets.length} 个，统计覆盖完整文件。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: packets.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: LocalizedText('没有匹配的数据包')),
                )
              : Column(
                  children: [
                    for (final packet in packets.take(500))
                      ListTile(
                        minTileHeight: 58,
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: LocalizedText(
                            '${packet.number}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        title: LocalizedText(
                          packet.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: LocalizedText(
                          '${packet.timestamp.toLocal().toIso8601String()} · '
                          '${captureBytesLabel(packet.capturedLength)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _showPacket(packet),
                      ),
                    if (packets.length > 500)
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: LocalizedText(
                          '当前筛选命中 ${packets.length} 个包，为保证流畅仅显示前 500 个。',
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: context.tr('选择 PCAP 或 PCAPNG 文件'),
      type: FileType.custom,
      allowedExtensions: const ['pcap', 'pcapng', 'cap'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() {
      _running = true;
      _progress = 0;
      _analysis = null;
      _error = null;
    });
    try {
      final analysis = await _service.analyze(
        path,
        onProgress: (read, total) {
          if (!mounted) return;
          setState(() => _progress = total == 0 ? 0 : read / total);
        },
      );
      if (mounted) setState(() => _analysis = analysis);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _showPacket(CapturePacket packet) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .88,
      minChildSize: .5,
      maxChildSize: .96,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LocalizedText(
              '数据包 #${packet.number}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StructuredDataViewer(
                payload: StructuredPayload(
                  rawText: const JsonEncoder.withIndent(
                    '  ',
                  ).convert(packet.toJson()),
                  rawBytes: packet.bytes,
                  contentType: 'packet',
                  source: 'PCAP',
                  metadata: packet.toJson(),
                  timestamp: packet.timestamp,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.onPick});
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  Icons.file_open_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      '分析已有抓包文件',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    LocalizedText('PCAP / PCAPNG · 全程离线，不创建 VPN'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.folder_open_rounded),
            label: const LocalizedText('选择抓包文件'),
          ),
        ],
      ),
    ),
  );
}

class _CaptureSummary extends StatelessWidget {
  const _CaptureSummary({required this.analysis});
  final CaptureAnalysis analysis;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: LocalizedText(
                  '文件概览',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              Chip(label: LocalizedText(analysis.format)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _metric('数据包', '${analysis.packetCount}'),
              _metric('线上字节', captureBytesLabel(analysis.byteCount)),
              _metric('文件大小', captureBytesLabel(analysis.fileSize)),
            ],
          ),
          const SizedBox(height: 12),
          LocalizedText(
            analysis.duration == null
                ? '没有可用的时间戳'
                : '采集跨度 ${analysis.duration}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _metric(String label, String value) => Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LocalizedText(
        value,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      LocalizedText(label, style: const TextStyle(fontSize: 12)),
    ],
  ),
);

class _ProtocolOverview extends StatelessWidget {
  const _ProtocolOverview({required this.analysis});
  final CaptureAnalysis analysis;
  static const colors = [
    Color(0xFF3578F6),
    Color(0xFF42B6E9),
    Color(0xFF16B79A),
    Color(0xFFF2A43A),
    Color(0xFF7B65D8),
    Color(0xFFE1638D),
    Color(0xFF6B7A90),
  ];
  @override
  Widget build(BuildContext context) {
    final entries = analysis.protocolBytes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LocalizedText(
              '协议分布',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            if (total == 0)
              const LocalizedText('没有可统计的数据包')
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final chart = SizedBox(
                    width: 190,
                    height: 190,
                    child: PieChart(
                      PieChartData(
                        centerSpaceRadius: 48,
                        sectionsSpace: 2,
                        sections: [
                          for (var i = 0; i < entries.length && i < 7; i++)
                            PieChartSectionData(
                              color: colors[i % colors.length],
                              value: entries[i].value.toDouble(),
                              radius: 34,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                  );
                  final legend = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < entries.length && i < 7; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: colors[i % colors.length],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              LocalizedText(
                                '${entries[i].key}  ${(entries[i].value / total * 100).toStringAsFixed(1)}%',
                              ),
                              const SizedBox(width: 10),
                              LocalizedText(
                                captureBytesLabel(entries[i].value),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                  return constraints.maxWidth >= 600
                      ? Row(
                          children: [chart, const SizedBox(width: 28), legend],
                        )
                      : Column(
                          children: [
                            chart,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: legend,
                            ),
                          ],
                        );
                },
              ),
          ],
        ),
      ),
    );
  }
}
