import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../services/iperf_command_service.dart';
import '../../../services/native_network_service.dart';
import '../../../state/app_state.dart';

class IperfPage extends StatefulWidget {
  const IperfPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<IperfPage> createState() => _IperfPageState();
}

class _IperfPageState extends State<IperfPage> {
  final _service = IperfCommandService();
  final _native = NativeNetworkService();
  final _terminalScrollController = ScrollController();
  final _controller = TextEditingController(
    text: 'iperf3 -c 192.168.1.1 -t 10',
  );
  var _mode = IperfMode.client;
  String _output = '';
  bool _outputSeeded = false;
  Map<String, String> _metrics = const {};
  List<double> _throughputMbps = const [];
  bool _running = false;
  bool _stopping = false;
  int _elapsedSeconds = 0;
  Timer? _elapsedTimer;
  Timer? _eventTimer;
  bool _pollingEvents = false;
  String _phase = '等待启动';
  double _throughputTotalMbps = 0;
  double _peakMbps = 0;
  int _throughputSamples = 0;
  int _intervalBytes = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_outputSeeded) return;
    _outputSeeded = true;
    _output = '${context.tr('选择模式并输入 iPerf3 命令。')}\n';
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _eventTimer?.cancel();
    if (_running) {
      unawaited(_native.stopIperf());
      unawaited(_native.stopForegroundTask());
    }
    _controller.dispose();
    _terminalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('iPerf3')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<IperfMode>(
            segments: const [
              ButtonSegment(
                value: IperfMode.client,
                icon: Icon(Icons.call_made),
                label: LocalizedText('Client'),
              ),
              ButtonSegment(
                value: IperfMode.server,
                icon: Icon(Icons.dns),
                label: LocalizedText('Server'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _running
                ? null
                : (values) => _changeMode(values.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !_running,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              label: LocalizedText('iPerf3 命令'),
              hintText: 'iperf3 -c 192.168.1.10 -t 10',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _templates()
                .map(
                  (item) => ActionChip(
                    label: LocalizedText(item.$1),
                    onPressed: _running
                        ? null
                        : () => _controller.text = item.$2,
                  ),
                )
                .toList(),
          ),
          if (Platform.isWindows || Platform.isLinux) ...[
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const ListTile(
                leading: Icon(Icons.desktop_windows_outlined),
                title: LocalizedText('桌面版已内置 iPerf 3.21'),
                subtitle: LocalizedText(
                  'Linux 与 Windows Release 均随包提供可执行文件，无需另行安装。参数仍经过同一套白名单校验。',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const LocalizedText('运行'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _running && !_stopping ? _stop : null,
                icon: const Icon(Icons.stop),
                label: LocalizedText(_stopping ? '停止中' : '停止'),
              ),
            ],
          ),
          if (_running) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: .48),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(
                    '${_stopping ? '正在停止原生会话' : _phase} · ${_formatElapsed(_elapsedSeconds)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 3),
                  if (_mode == IperfMode.client) ...[
                    const SizedBox(height: 7),
                    LocalizedText(
                      '目标未监听时会在 5 秒内返回；完整测试也设有超时保护。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_metrics.isNotEmpty) ...[
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: _metrics.entries
                  .map(
                    (entry) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            LocalizedText(
                              entry.value,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            LocalizedText(
                              entry.key,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (_throughputMbps.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: LocalizedText(
                              '实时吞吐曲线',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          LocalizedText(
                            '${_throughputMbps.last.toStringAsFixed(1)} Mbps',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 150,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _IperfChartPainter(
                            _throughputMbps,
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          Card(
            color: const Color(0xFF111719),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: LocalizedText(
                          '输出',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: _output)),
                        icon: const Icon(Icons.copy, color: Colors.white70),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  SizedBox(
                    height: 300,
                    child: SingleChildScrollView(
                      controller: _terminalScrollController,
                      child: SelectableText(
                        _output,
                        style: const TextStyle(
                          color: Color(0xFFB9F6CA),
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          LocalizedText(
            '安全说明：命令只经过 iPerf3 白名单解析，不会交给系统 Shell。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  void _changeMode(IperfMode mode) {
    setState(() {
      _mode = mode;
      _controller.text = mode == IperfMode.server
          ? 'iperf3 -s'
          : 'iperf3 -c 192.168.1.1 -t 10';
    });
  }

  List<(String, String)> _templates() => _mode == IperfMode.server
      ? [('默认 Server', 'iperf3 -s'), ('单次连接', 'iperf3 -s -1')]
      : [
          ('TCP', 'iperf3 -c 192.168.1.1 -t 10'),
          ('UDP', 'iperf3 -c 192.168.1.1 -u -b 100M'),
          ('反向', 'iperf3 -c 192.168.1.1 -R'),
          ('4 流', 'iperf3 -c 192.168.1.1 -P 4'),
        ];

  Future<void> _start() async {
    final validation = _service.validate(_controller.text, _mode);
    if (!validation.isValid) {
      setState(() => _output = '${context.tr('参数错误：${validation.error}')}\n');
      return;
    }
    setState(() {
      _running = true;
      _stopping = false;
      _elapsedSeconds = 0;
      _phase = _mode == IperfMode.server ? '正在创建监听' : '正在连接目标';
      _metrics = const {};
      _throughputMbps = const [];
      _throughputTotalMbps = 0;
      _peakMbps = 0;
      _throughputSamples = 0;
      _intervalBytes = 0;
      _output =
          '\$ ${_controller.text}\n\n'
          '${context.tr('正在启动 iPerf 3.21 ${_mode.name}…')}\n';
    });
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    try {
      await _native.startForegroundTask(
        'iPerf3 ${_mode == IperfMode.server ? 'Server' : 'Client'} 运行中',
        _mode == IperfMode.server ? '等待客户端连接，可点击返回停止' : _controller.text,
      );
      final run = _native.runIperf(validation.arguments);
      _eventTimer?.cancel();
      _eventTimer = Timer.periodic(
        const Duration(milliseconds: 120),
        (_) => unawaited(_drainIperfEvents()),
      );
      await _confirmNativeSession(validation.arguments);
      final result = _mode == IperfMode.client
          ? await run.timeout(
              _service.clientExecutionTimeout(validation.arguments),
              onTimeout: () async {
                await _native.stopIperf();
                throw TimeoutException('iPerf3 会话超过预期时间，已自动停止');
              },
            )
          : await run;
      await _stopEventPollingAndDrain();
      final parsed = _parseOutput(result.output);
      if (!mounted) return;
      setState(() {
        _metrics = {..._metrics, ...parsed.metrics};
        if (_throughputMbps.isEmpty && parsed.intervalsMbps.isNotEmpty) {
          _throughputMbps = parsed.intervalsMbps;
        }
        if (_stopping) {
          _appendTerminal('\n[已停止] iPerf3 会话已由用户结束。\n');
        } else {
          _appendTerminal(
            result.ok
                ? '\n[完成] iPerf3 测试已结束。\n'
                : '\n[失败 ${result.exitCode}] ${parsed.error ?? _plainError(result.output)}\n',
          );
        }
      });
      _scrollTerminalAfterFrame();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _appendTerminal('\n运行失败：$error\n'));
        _scrollTerminalAfterFrame();
      }
    } finally {
      await _stopEventPollingAndDrain();
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      await _native.stopForegroundTask();
      if (mounted) {
        setState(() {
          _running = false;
          _stopping = false;
        });
      }
    }
  }

  Future<void> _confirmNativeSession(List<String> arguments) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || !_running) return;
      if (await _native.isIperfRunning()) {
        final port = _service.serverPort(arguments);
        setState(() {
          if (_mode == IperfMode.server) {
            if (_phase != '正在传输数据') {
              _phase = '服务端已监听 :$port';
              _appendTerminal(
                '\n[服务端已启动]\n'
                '正在监听 0.0.0.0:$port，等待 iPerf3 Client 连接。\n'
                '这是持续运行状态，可随时点击“停止”。\n',
              );
            }
          } else {
            if (_phase != '正在传输数据') {
              _phase = '客户端会话已启动';
              _appendTerminal('\n[客户端已启动]\n正在连接服务端并准备测试流量…\n');
            }
          }
        });
        _scrollTerminalAfterFrame();
        return;
      }
    }
  }

  Future<void> _stop() async {
    setState(() {
      _stopping = true;
      _appendTerminal('\n[正在停止会话…]\n');
    });
    try {
      final stopped = await _native.stopIperf().timeout(
        const Duration(seconds: 3),
      );
      if (!stopped && mounted) {
        setState(() => _appendTerminal('[原生会话已结束或尚未完成初始化]\n'));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _appendTerminal('[停止请求失败：$error]\n'));
      }
    }
    _scrollTerminalAfterFrame();
  }

  Future<void> _drainIperfEvents() async {
    if (_pollingEvents) return;
    _pollingEvents = true;
    final events = <Map<String, Object?>>[];
    try {
      for (var index = 0; index < 64; index++) {
        final raw = await _native.pollIperfEvent();
        if (raw == null) break;
        try {
          events.add(jsonDecode(raw) as Map<String, Object?>);
        } on Object {
          // A malformed native event is ignored without stopping the session.
        }
      }
      if (events.isEmpty || !mounted) return;
      setState(() {
        for (final event in events) {
          _applyLiveEvent(event);
        }
      });
      _scrollTerminalAfterFrame();
    } finally {
      _pollingEvents = false;
    }
  }

  Future<void> _stopEventPollingAndDrain() async {
    _eventTimer?.cancel();
    _eventTimer = null;
    for (var attempt = 0; attempt < 20 && _pollingEvents; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _drainIperfEvents();
  }

  void _applyLiveEvent(Map<String, Object?> event) {
    final name = event['event'] as String?;
    final data = event['data'];
    if (name == 'start' && data is Map<String, Object?>) {
      _phase = '正在传输数据';
      final target = data['connecting_to'] as Map<String, Object?>?;
      if (target != null) {
        _appendTerminal(
          '\nConnecting to host ${target['host']}, port ${target['port']}\n',
        );
      } else {
        _appendTerminal('\n客户端已连接，测试开始。\n');
      }
      _appendTerminal(
        '[ ID] Interval           Transfer       Bitrate          Extra\n',
      );
      return;
    }
    if (name == 'interval' && data is Map<String, Object?>) {
      final rows = _measurementRows(data, interval: true);
      for (final entry in rows) {
        _appendTerminal(_terminalRow(entry.$1, entry.$2));
      }
      if (rows.isNotEmpty) _recordMeasurement(rows.first.$2);
      return;
    }
    if (name == 'end' && data is Map<String, Object?>) {
      _phase = '正在整理结果';
      _appendTerminal(
        '-----------------------------------------------------------\n',
      );
      for (final entry in _measurementRows(data, interval: false)) {
        _appendTerminal(_terminalRow(entry.$1, entry.$2));
      }
      return;
    }
    if (name == 'error') {
      if (_stopping) return;
      final message = data is String ? data : '$data';
      _appendTerminal('\niperf3: error - $message\n');
    }
  }

  List<(String, Map<String, Object?>)> _measurementRows(
    Map<String, Object?> data, {
    required bool interval,
  }) {
    final keys = interval
        ? const ['sum', 'sum_bidir_reverse']
        : const ['sum_sent', 'sum_received', 'sum'];
    final rows = <(String, Map<String, Object?>)>[];
    for (final key in keys) {
      final value = data[key];
      if (value is! Map<String, Object?>) continue;
      final label = switch (key) {
        'sum_sent' => 'TX',
        'sum_received' => 'RX',
        'sum_bidir_reverse' => 'RX',
        _ => 'SUM',
      };
      rows.add((label, value));
    }
    if (rows.isNotEmpty) return rows;
    final streams = data['streams'];
    if (streams is List<Object?> && streams.isNotEmpty) {
      final row = streams.first;
      if (row is Map<String, Object?>) rows.add(('  1', row));
    }
    return rows;
  }

  String _terminalRow(String label, Map<String, Object?> row) {
    final start = (row['start'] as num?)?.toDouble() ?? 0;
    final end = (row['end'] as num?)?.toDouble() ?? 0;
    final bytes = (row['bytes'] as num?)?.toInt() ?? 0;
    final bits = (row['bits_per_second'] as num?)?.toDouble() ?? 0;
    final extras = <String>[];
    final retransmits = (row['retransmits'] as num?)?.toInt();
    if (retransmits != null) extras.add('$retransmits retr');
    final jitter = (row['jitter_ms'] as num?)?.toDouble();
    if (jitter != null) extras.add('${jitter.toStringAsFixed(2)} ms');
    final lost = (row['lost_packets'] as num?)?.toInt();
    final packets = (row['packets'] as num?)?.toInt();
    final lostPercent = (row['lost_percent'] as num?)?.toDouble();
    if (lost != null && packets != null && lostPercent != null) {
      extras.add('$lost/$packets (${lostPercent.toStringAsFixed(1)}%)');
    }
    if (row['omitted'] == true) extras.add('(omitted)');
    return '[${label.padLeft(3)}] '
        '${start.toStringAsFixed(2).padLeft(5)}-'
        '${end.toStringAsFixed(2).padRight(5)} sec  '
        '${_transfer(bytes).padLeft(11)}  '
        '${_terminalBitrate(bits).padLeft(15)}  '
        '${extras.join('  ')}\n';
  }

  void _recordMeasurement(Map<String, Object?> row) {
    if (row['omitted'] == true) return;
    final bits = (row['bits_per_second'] as num?)?.toDouble();
    if (bits == null) return;
    final mbps = bits / 1000000;
    _throughputSamples++;
    _throughputTotalMbps += mbps;
    _peakMbps = math.max(_peakMbps, mbps);
    _intervalBytes += (row['bytes'] as num?)?.toInt() ?? 0;
    _throughputMbps = [..._throughputMbps, mbps];
    if (_throughputMbps.length > 120) {
      _throughputMbps = _throughputMbps.sublist(_throughputMbps.length - 120);
    }
    final metrics = <String, String>{
      '当前吞吐': _bitrate(bits),
      '平均吞吐':
          '${(_throughputTotalMbps / _throughputSamples).toStringAsFixed(2)} Mbps',
      '峰值吞吐': '${_peakMbps.toStringAsFixed(2)} Mbps',
      '实时传输': _transfer(_intervalBytes),
    };
    final retransmits = (row['retransmits'] as num?)?.toInt();
    if (retransmits != null) metrics['本周期重传'] = '$retransmits';
    final jitter = (row['jitter_ms'] as num?)?.toDouble();
    if (jitter != null) metrics['UDP 抖动'] = '${jitter.toStringAsFixed(2)} ms';
    final lost = (row['lost_percent'] as num?)?.toDouble();
    if (lost != null) metrics['UDP 丢包'] = '${lost.toStringAsFixed(2)}%';
    _metrics = metrics;
  }

  void _appendTerminal(String text) {
    _output += text;
    if (_output.length > 65536) {
      _output =
          '${context.tr('[较早的终端输出已截断]')}\n'
          '${_output.substring(_output.length - 60000)}';
    }
  }

  void _scrollTerminalAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_terminalScrollController.hasClients) return;
      _terminalScrollController.animateTo(
        _terminalScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _plainError(String raw) {
    final trimmed = raw.trim();
    return trimmed.startsWith('{') ? 'iPerf3 会话未正常完成' : trimmed;
  }

  String _transfer(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GBytes';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MBytes';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(2)} KBytes';
    return '$bytes Bytes';
  }

  String _terminalBitrate(double bitsPerSecond) {
    if (bitsPerSecond >= 1000000000) {
      return '${(bitsPerSecond / 1000000000).toStringAsFixed(2)} Gbits/sec';
    }
    if (bitsPerSecond >= 1000000) {
      return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mbits/sec';
    }
    return '${(bitsPerSecond / 1000).toStringAsFixed(2)} Kbits/sec';
  }

  String _formatElapsed(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';

  _IperfParsedOutput _parseOutput(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final metrics = <String, String>{};
      final intervals = <double>[];
      for (final interval in json['intervals'] as List<Object?>? ?? const []) {
        final row = interval as Map<String, Object?>;
        final sum = row['sum'] as Map<String, Object?>?;
        final bits = (sum?['bits_per_second'] as num?)?.toDouble();
        if (bits != null) intervals.add(bits / 1000000);
      }
      final end = json['end'] as Map<String, Object?>? ?? const {};
      final error = json['error'] as String?;
      final sent = end['sum_sent'] as Map<String, Object?>?;
      final received = end['sum_received'] as Map<String, Object?>?;
      final udp = end['sum'] as Map<String, Object?>?;
      final sentBits = (sent?['bits_per_second'] as num?)?.toDouble();
      final receivedBits = (received?['bits_per_second'] as num?)?.toDouble();
      final udpBits = (udp?['bits_per_second'] as num?)?.toDouble();
      if (sentBits != null) metrics['发送'] = _bitrate(sentBits);
      if (receivedBits != null) metrics['接收'] = _bitrate(receivedBits);
      if (sentBits == null && receivedBits == null && udpBits != null) {
        metrics['吞吐'] = _bitrate(udpBits);
      }
      final retransmits = sent?['retransmits'] as num?;
      if (retransmits != null) metrics['TCP 重传'] = '${retransmits.toInt()}';
      final jitter = udp?['jitter_ms'] as num?;
      if (jitter != null) metrics['UDP 抖动'] = '${jitter.toStringAsFixed(2)} ms';
      final lostPercent = udp?['lost_percent'] as num?;
      if (lostPercent != null)
        metrics['UDP 丢包'] = '${lostPercent.toStringAsFixed(2)}%';
      return _IperfParsedOutput(
        metrics: metrics,
        intervalsMbps: intervals,
        error: error,
      );
    } on Object {
      return _IperfParsedOutput(
        metrics: const {},
        intervalsMbps: const [],
        error: null,
      );
    }
  }

  String _bitrate(double bitsPerSecond) {
    if (bitsPerSecond >= 1000000000) {
      return '${(bitsPerSecond / 1000000000).toStringAsFixed(2)} Gbps';
    }
    return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mbps';
  }
}

class _IperfParsedOutput {
  const _IperfParsedOutput({
    required this.metrics,
    required this.intervalsMbps,
    required this.error,
  });
  final Map<String, String> metrics;
  final List<double> intervalsMbps;
  final String? error;
}

class _IperfChartPainter extends CustomPainter {
  const _IperfChartPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 42.0;
    const bottomPadding = 18.0;
    final plot = Rect.fromLTRB(
      left,
      5,
      size.width - 5,
      size.height - bottomPadding,
    );
    final maximum = math.max(1.0, values.reduce(math.max) * 1.12);
    final grid = Paint()
      ..color = color.withValues(alpha: .12)
      ..strokeWidth = 1;
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (var row = 0; row <= 3; row++) {
      final y = plot.top + plot.height * row / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      text.text = TextSpan(
        text: (maximum * (3 - row) / 3).toStringAsFixed(0),
        style: const TextStyle(fontSize: 9, color: Color(0xFF66859D)),
      );
      text.layout();
      text.paint(canvas, Offset(2, y - 5));
    }
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = plot.left + index / math.max(1, values.length - 1) * plot.width;
      final y = plot.bottom - values[index] / maximum * plot.height;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = color);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _IperfChartPainter oldDelegate) => true;
}
