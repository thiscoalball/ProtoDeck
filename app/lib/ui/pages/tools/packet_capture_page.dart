import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

import '../../../models/structured_payload.dart';
import '../../../services/download_destination_service.dart';
import '../../../services/pcap_analysis_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../widgets/structured_data_viewer.dart';

class PacketCapturePage extends StatefulWidget {
  const PacketCapturePage({super.key, required this.appState});

  final AppState appState;

  @override
  State<PacketCapturePage> createState() => _PacketCapturePageState();
}

class _PacketCapturePageState extends State<PacketCapturePage> {
  final _service = PcapAnalysisService();
  CaptureAnalysis? _analysis;
  bool _running = false;
  double _progress = 0;
  String? _error;
  final _query = TextEditingController();
  String _protocol = '全部';
  String? _lastFilePath;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _restoreDraft();
  }

  @override
  void dispose() {
    _service.cancel();
    if (_draftLoaded) {
      unawaited(_drafts.save('tool.packet_capture', _draftValue()));
    }
    _drafts.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('离线抓包分析'),
        actions: [
          if (analysis != null)
            PopupMenuButton<String>(
              tooltip: context.tr('导出分析结果'),
              onSelected: _exportAnalysis,
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'json', child: LocalizedText('导出分析 JSON')),
                PopupMenuItem(value: 'csv', child: LocalizedText('导出会话 CSV')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            _IntroCard(onPick: _running ? null : _pickFile),
            if (_lastFilePath case final path?) ...[
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const LocalizedText('上次打开的抓包'),
                  subtitle: Text(
                    path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.refresh_rounded),
                  onTap: _running ? null : () => _analyzePath(path),
                ),
              ),
            ],
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
              _ProtocolHierarchy(analysis: analysis),
              const SizedBox(height: 18),
              _CaptureIoGraph(analysis: analysis),
              const SizedBox(height: 18),
              _EndpointOverview(analysis: analysis),
              const SizedBox(height: 18),
              _FlowOverview(analysis: analysis),
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
    final query = _query.text.trim().toLowerCase();
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
          controller: _query,
          onChanged: (_) {
            setState(() {});
            _saveDraft();
          },
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
                onSelected: (_) {
                  setState(() => _protocol = value);
                  _saveDraft();
                },
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
    await _analyzePath(path);
  }

  Future<void> _analyzePath(String path) async {
    if (!await File(path).exists()) {
      if (!mounted) return;
      setState(() {
        _lastFilePath = null;
        _error = '上次文件已不存在或访问权限已失效，请重新选择';
      });
      _saveDraft();
      return;
    }
    setState(() {
      _running = true;
      _progress = 0;
      _analysis = null;
      _error = null;
      _lastFilePath = path;
    });
    _saveDraft();
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

  Future<void> _exportAnalysis(String format) async {
    final analysis = _analysis;
    if (analysis == null) return;
    try {
      final extension = format == 'csv' ? 'csv' : 'json';
      final content = format == 'csv'
          ? _flowsCsv(analysis.flows)
          : const JsonEncoder.withIndent('  ').convert({
              'sourceFile': analysis.path,
              'format': analysis.format,
              'fileSize': analysis.fileSize,
              'packetCount': analysis.packetCount,
              'byteCount': analysis.byteCount,
              'startedAt': analysis.startedAt?.toIso8601String(),
              'endedAt': analysis.endedAt?.toIso8601String(),
              'protocolBytes': analysis.protocolBytes,
              'protocolHierarchy': [
                for (final item in analysis.protocolHierarchy)
                  {
                    'path': item.path,
                    'packetCount': item.packetCount,
                    'byteCount': item.byteCount,
                  },
              ],
              'endpoints': analysis.endpoints,
              'ioBuckets': [
                for (final item in analysis.ioBuckets)
                  {
                    'startedAt': item.startedAt.toIso8601String(),
                    'packetCount': item.packetCount,
                    'byteCount': item.byteCount,
                  },
              ],
              'flows': [for (final flow in analysis.flows) _flowJson(flow)],
            });
      final saved = await DownloadDestinationService.saveBytes(
        bytes: Uint8List.fromList(utf8.encode(content)),
        dialogTitle: context.tr(format == 'csv' ? '导出会话 CSV' : '导出分析 JSON'),
        fileName: 'protodeck_capture_analysis.$extension',
        allowedExtensions: [extension],
        mimeType: format == 'csv' ? 'text/csv' : 'application/json',
      );
      if (saved == null) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedText('已保存：${saved.displayLocation}')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText('导出失败：$error')));
      }
    }
  }

  static Map<String, Object?> _flowJson(CaptureFlow flow) => {
    'protocol': flow.protocol,
    'endpointA': flow.endpointA,
    'endpointB': flow.endpointB,
    'packetCount': flow.packetCount,
    'byteCount': flow.byteCount,
    'bytesAToB': flow.bytesAToB,
    'bytesBToA': flow.bytesBToA,
    'firstSeen': flow.firstSeen.toIso8601String(),
    'lastSeen': flow.lastSeen.toIso8601String(),
    'details': flow.details,
  };

  static String _flowsCsv(List<CaptureFlow> flows) {
    String cell(Object? value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';
    return [
      [
        'protocol',
        'endpoint_a',
        'endpoint_b',
        'packets',
        'bytes_total',
        'bytes_a_to_b',
        'bytes_b_to_a',
        'first_seen',
        'last_seen',
        'application_details',
      ],
      for (final flow in flows)
        [
          flow.protocol,
          flow.endpointA,
          flow.endpointB,
          flow.packetCount,
          flow.byteCount,
          flow.bytesAToB,
          flow.bytesBToA,
          flow.firstSeen.toIso8601String(),
          flow.lastSeen.toIso8601String(),
          flow.details.join(' | '),
        ],
    ].map((row) => row.map(cell).join(',')).join('\r\n');
  }

  Map<String, Object?> _draftValue() => {
    'query': _query.text,
    'protocol': _protocol,
    'lastFilePath': _lastFilePath,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.packet_capture');
    if (!mounted) return;
    final payload = draft?.payload;
    if (payload != null) {
      _query.text = payload['query']?.toString() ?? '';
      _protocol = payload['protocol']?.toString() ?? '全部';
      _lastFilePath = payload['lastFilePath']?.toString();
    }
    _draftLoaded = true;
    setState(() {});
  }

  void _saveDraft() {
    if (_draftLoaded) {
      _drafts.scheduleSave('tool.packet_capture', _draftValue());
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

class _ProtocolHierarchy extends StatelessWidget {
  const _ProtocolHierarchy({required this.analysis});

  final CaptureAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final roots = analysis.protocolHierarchy
        .where((item) => item.path.length == 1)
        .toList(growable: false);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: LocalizedText(
              '协议层级',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: LocalizedText(
              '按网络层 → 传输层 → 应用层统计完整抓包文件',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (roots.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: LocalizedText('没有可识别的协议层级'),
            )
          else
            for (final root in roots) _protocolNode(context, root),
        ],
      ),
    );
  }

  Widget _protocolNode(BuildContext context, CaptureProtocolStat item) {
    final children = analysis.protocolHierarchy
        .where(
          (candidate) =>
              candidate.path.length == item.path.length + 1 &&
              _startsWith(candidate.path, item.path),
        )
        .toList(growable: false);
    final percent = analysis.byteCount == 0
        ? 0.0
        : item.byteCount / analysis.byteCount * 100;
    final title = Row(
      children: [
        Expanded(
          child: Text(
            item.path.last,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          '${percent.toStringAsFixed(1)}% · ${captureBytesLabel(item.byteCount)}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    if (children.isEmpty) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(
          left: 18.0 + (item.path.length - 1) * 18,
          right: 18,
        ),
        title: title,
        subtitle: LocalizedText('${item.packetCount} 个包'),
      );
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.only(
        left: 18.0 + (item.path.length - 1) * 18,
        right: 18,
      ),
      title: title,
      subtitle: LocalizedText('${item.packetCount} 个包'),
      children: [for (final child in children) _protocolNode(context, child)],
    );
  }

  static bool _startsWith(List<String> value, List<String> prefix) {
    if (prefix.length > value.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (value[index] != prefix[index]) return false;
    }
    return true;
  }
}

class _CaptureIoGraph extends StatelessWidget {
  const _CaptureIoGraph({required this.analysis});

  final CaptureAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final buckets = _compact(analysis.ioBuckets, 120);
    final peak = buckets.fold<int>(
      1,
      (value, item) => math.max(value, item.$2),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: LocalizedText(
                    'I/O 速率',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                LocalizedText('峰值 ${captureBytesLabel(peak)}/s'),
              ],
            ),
            const SizedBox(height: 14),
            if (buckets.isEmpty)
              const LocalizedText('没有可用的时间序列')
            else
              SizedBox(
                height: 190,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: math.max(1, buckets.length - 1).toDouble(),
                    minY: 0,
                    maxY: peak * 1.15,
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(drawVerticalLine: false),
                    titlesData: const FlTitlesData(
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => [
                          for (final spot in spots)
                            LineTooltipItem(
                              '${buckets[spot.x.round()].$1.toLocal().toIso8601String()}\n'
                              '${captureBytesLabel(spot.y.round())}/s',
                              const TextStyle(color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var index = 0; index < buckets.length; index++)
                            FlSpot(
                              index.toDouble(),
                              buckets[index].$2.toDouble(),
                            ),
                        ],
                        color: Theme.of(context).colorScheme.primary,
                        barWidth: 2.5,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static List<(DateTime, int)> _compact(
    List<CaptureIoBucket> source,
    int maximum,
  ) {
    if (source.isEmpty) return const [];
    final width = math.max(1, (source.length / maximum).ceil());
    final output = <(DateTime, int)>[];
    for (var start = 0; start < source.length; start += width) {
      final end = math.min(source.length, start + width);
      var bytes = 0;
      for (var index = start; index < end; index++) {
        bytes += source[index].byteCount;
      }
      output.add((source[start].startedAt, (bytes / (end - start)).round()));
    }
    return output;
  }
}

class _EndpointOverview extends StatelessWidget {
  const _EndpointOverview({required this.analysis});

  final CaptureAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final entries = analysis.endpoints.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final shown = entries.take(20).toList(growable: false);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 10, 8),
            child: Row(
              children: [
                const Expanded(
                  child: LocalizedText(
                    '端点排行',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                LocalizedText('${entries.length} 个端点'),
              ],
            ),
          ),
          for (var index = 0; index < shown.length; index++)
            ListTile(
              dense: true,
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: SelectableText(
                shown[index].key,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              subtitle: LinearProgressIndicator(
                value: shown.first.value == 0
                    ? 0
                    : shown[index].value / shown.first.value,
              ),
              trailing: Text(captureBytesLabel(shown[index].value)),
              onLongPress: () =>
                  Clipboard.setData(ClipboardData(text: shown[index].key)),
            ),
          if (entries.length > shown.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
              child: LocalizedText(
                '按流量显示前 ${shown.length} 个端点，共 ${entries.length} 个。',
              ),
            ),
        ],
      ),
    );
  }
}

class _FlowOverview extends StatelessWidget {
  const _FlowOverview({required this.analysis});

  final CaptureAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final flows = analysis.flows.take(30).toList(growable: false);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                const Expanded(
                  child: LocalizedText(
                    '双向会话',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(context.l10n.toolPages.flowCount(analysis.flows.length)),
              ],
            ),
          ),
          if (flows.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: LocalizedText('没有可聚合的 IP 会话'),
            )
          else ...[
            for (final flow in flows)
              ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Text(
                    flow.protocol.length <= 4
                        ? flow.protocol
                        : flow.protocol.substring(0, 4),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                title: Text(
                  '${flow.endpointA} ↔ ${flow.endpointB}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                subtitle: LocalizedText(
                  '${flow.packetCount} 个包 · ${captureBytesLabel(flow.byteCount)} · ${flow.duration}',
                ),
                trailing: IconButton(
                  tooltip: context.tr('复制会话摘要'),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _flowText(flow))),
                  icon: const Icon(Icons.copy_rounded),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _flowMetric(
                    context,
                    '${flow.endpointA} → ${flow.endpointB}',
                    captureBytesLabel(flow.bytesAToB),
                  ),
                  _flowMetric(
                    context,
                    '${flow.endpointB} → ${flow.endpointA}',
                    captureBytesLabel(flow.bytesBToA),
                  ),
                  _flowMetric(
                    context,
                    context.tr('首次 / 末次'),
                    '${flow.firstSeen.toLocal().toIso8601String()}\n'
                    '${flow.lastSeen.toLocal().toIso8601String()}',
                  ),
                  if (flow.details.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const LocalizedText(
                      '应用层线索',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    for (final detail in flow.details)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SelectableText(
                          detail,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                  ],
                ],
              ),
            if (analysis.flows.length > flows.length)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                child: LocalizedText(
                  '按流量显示前 ${flows.length} 个会话，共 ${analysis.flows.length} 个。',
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _flowText(CaptureFlow flow) => [
    '${flow.protocol} ${flow.endpointA} ↔ ${flow.endpointB}',
    'Packets: ${flow.packetCount}',
    'Bytes: ${flow.byteCount}',
    '${flow.endpointA} -> ${flow.endpointB}: ${flow.bytesAToB}',
    '${flow.endpointB} -> ${flow.endpointA}: ${flow.bytesBToA}',
    'First: ${flow.firstSeen.toIso8601String()}',
    'Last: ${flow.lastSeen.toIso8601String()}',
    ...flow.details,
  ].join('\n');

  static Widget _flowMetric(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SelectableText(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      );
}
