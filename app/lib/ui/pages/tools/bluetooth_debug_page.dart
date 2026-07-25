import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../models/structured_payload.dart';
import '../../../services/bluetooth_debug_service.dart';
import '../../../services/socket_debug_service.dart';
import '../../widgets/structured_data_viewer.dart';

class BluetoothDebugPage extends StatefulWidget {
  const BluetoothDebugPage({super.key});

  @override
  State<BluetoothDebugPage> createState() => _BluetoothDebugPageState();
}

class _BluetoothDebugPageState extends State<BluetoothDebugPage> {
  static const _sppUuid = '00001101-0000-1000-8000-00805F9B34FB';
  static const _serviceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const _characteristicUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
  final _service = BluetoothDebugService();
  final _classicUuid = TextEditingController(text: _sppUuid);
  final _serviceId = TextEditingController(text: _serviceUuid);
  final _characteristicId = TextEditingController(text: _characteristicUuid);
  final _payload = TextEditingController(text: 'Hello Bluetooth');
  final _search = TextEditingController();
  final _devices = <String, Map<Object?, Object?>>{};
  final _rssiHistory = <String, List<_RssiPoint>>{};
  final _notifyEnabled = <String>{};
  final _logs = <Map<Object?, Object?>>[];
  List<Map<Object?, Object?>> _services = const [];
  Map<Object?, Object?> _status = const {};
  Timer? _poller;
  Timer? _scanWatchdog;
  DateTime? _scanStartedAt;
  int _section = 0;
  bool _scanning = false;
  bool _server = false;
  bool _hex = false;
  bool _hideUnnamed = false;
  bool _onlyConnectable = false;
  int _minRssi = -100;
  String _sort = 'rssi';
  String? _scanIssue;
  String? _connectedAddress;
  String _connectionState = '未连接';

  @override
  void initState() {
    super.initState();
    _initialize();
    _poller = Timer.periodic(const Duration(milliseconds: 180), (_) => _poll());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _scanWatchdog?.cancel();
    if (!Platform.isWindows && !Platform.isLinux) {
      _service.stopBleScan();
      _service.stopClassicScan();
      _service.disconnectBle();
      _service.stopClassic();
    }
    for (final value in [
      _classicUuid,
      _serviceId,
      _characteristicId,
      _payload,
      _search,
    ]) {
      value.dispose();
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      var status = await _service.status();
      if (Platform.isWindows || Platform.isLinux) {
        if (!mounted) return;
        setState(() {
          _status = status;
          _scanIssue = status['reason']?.toString() ?? 'Windows 蓝牙调试暂不可用';
        });
        return;
      }
      final apiLevel = status['apiLevel'] as int? ?? 31;
      final requested = apiLevel >= 31
          ? await [
              Permission.bluetoothScan,
              Permission.bluetoothConnect,
            ].request()
          : await [Permission.locationWhenInUse].request();
      if (apiLevel >= 31) {
        // Some OEM Bluetooth stacks still gate complete advertisement results
        // behind location even when Nearby devices is granted. It is optional
        // for the normal Android 12+ path, so denial must not block scanning.
        await Permission.locationWhenInUse.request();
      }
      status = await _service.status();
      final scanGranted =
          status['permissions'] is Map &&
          (status['permissions'] as Map)['scan'] == true;
      final denied = requested.values.any(
        (value) => value.isDenied || value.isPermanentlyDenied,
      );
      List<Map<Object?, Object?>> paired = const [];
      if (status['permissions'] is Map &&
          (status['permissions'] as Map)['connect'] == true) {
        paired = await _service.bondedDevices();
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _scanIssue = !scanGranted || denied
            ? '附近设备权限未授予，Android 不会返回扫描结果'
            : (apiLevel < 31 && status['locationEnabled'] != true
                  ? 'Android 10/11 扫描需要开启系统定位服务'
                  : null);
        for (final value in paired) {
          final address = value['address'] as String?;
          if (address != null) {
            _devices[address] = {...value, 'bonded': true};
          }
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _scanIssue = '$error');
    }
  }

  List<Map<Object?, Object?>> get _visibleDevices {
    final query = _search.text.trim().toLowerCase();
    final values = _devices.values.where((device) {
      final name = _deviceName(device).toLowerCase();
      final address = device['address']?.toString().toLowerCase() ?? '';
      final rssi = device['rssi'] as int?;
      if (_hideUnnamed && name == '未命名设备') return false;
      if (_onlyConnectable && device['connectable'] == false) return false;
      return (rssi == null || rssi >= _minRssi) &&
          (query.isEmpty || name.contains(query) || address.contains(query));
    }).toList();
    values.sort((left, right) {
      if (_sort == 'name') {
        return _deviceName(left).compareTo(_deviceName(right));
      }
      if (_sort == 'seen') {
        return (right['seenAt'] as int? ?? 0).compareTo(
          left['seenAt'] as int? ?? 0,
        );
      }
      return (right['rssi'] as int? ?? -127).compareTo(
        left['rssi'] as int? ?? -127,
      );
    });
    return values;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('蓝牙调试助手'),
      actions: [
        IconButton(
          onPressed: _initialize,
          icon: const Icon(Icons.refresh),
          tooltip: context.tr('刷新状态'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusCard(),
        if (Platform.isWindows || Platform.isLinux) ...[
          const SizedBox(height: 14),
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: LocalizedText(
                '桌面首版暂不开放蓝牙操作区。网络、SSH、API、TCP/UDP、抓包解析等能力不受影响；'
                '在 WinRT BLE/GATT 与 RFCOMM 会话生命周期完整实现前，这里不会展示不可用按钮或模拟设备。',
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.bluetooth_searching),
                label: LocalizedText('BLE'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.bluetooth_connected),
                label: LocalizedText('经典蓝牙'),
              ),
            ],
            selected: {_section},
            onSelectionChanged: (value) => setState(() {
              _section = value.first;
              _devices.clear();
              _services = const [];
              _scanning = false;
              _initialize();
            }),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: LocalizedText('Central / Client'),
              ),
              ButtonSegment(
                value: true,
                label: LocalizedText('Peripheral / Server'),
              ),
            ],
            selected: {_server},
            onSelectionChanged: (value) =>
                setState(() => _server = value.first),
          ),
          const SizedBox(height: 14),
          if (_server) _serverPanel() else _clientPanel(),
          const SizedBox(height: 14),
          _sendPanel(),
          const SizedBox(height: 18),
          Row(
            children: [
              LocalizedText(
                '事件与数据',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: _logs.isEmpty ? null : () => setState(_logs.clear),
                child: const LocalizedText('清空'),
              ),
            ],
          ),
          if (_logs.isEmpty)
            const Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: LocalizedText('扫描、连接及收发事件会显示在这里')),
              ),
            )
          else
            ..._logs.take(100).map(_logTile),
        ],
      ],
    ),
  );

  Widget _statusCard() {
    final supported = _status['supported'] == true;
    final enabled = _status['enabled'] == true;
    final permissions = _status['permissions'] is Map
        ? _status['permissions'] as Map
        : const {};
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Icon(
                    enabled ? Icons.bluetooth : Icons.bluetooth_disabled,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        !supported
                            ? (Platform.isWindows || Platform.isLinux
                                  ? '桌面蓝牙适配尚未接入'
                                  : '设备不支持蓝牙')
                            : (enabled ? '蓝牙已开启' : '蓝牙未开启'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      LocalizedText(
                        Platform.isWindows || Platform.isLinux
                            ? '当前桌面版仍可使用网络与协议工具；BT/BLE 将按平台原生会话模型接入。'
                            : 'BLE ${_status['ble'] == true ? '可用' : '不可用'} · '
                                  '广播 ${_status['advertising'] == true ? '可用' : '不支持'} · '
                                  '扩展广播 ${_status['extendedAdvertising'] == true ? '支持' : '兼容模式'} · '
                                  'Android API ${_status['apiLevel'] ?? '-'}',
                      ),
                    ],
                  ),
                ),
                _statusPill(
                  permissions['scan'] == true ? '扫描权限正常' : '缺少扫描权限',
                  permissions['scan'] == true ? Colors.green : Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 10),
            LocalizedText('连接状态：$_connectionState'),
            if (_scanIssue != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 19),
                    const SizedBox(width: 8),
                    Expanded(child: LocalizedText(_scanIssue!)),
                    if (!Platform.isWindows && !Platform.isLinux)
                      TextButton(
                        onPressed: openAppSettings,
                        child: const LocalizedText('系统设置'),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: LocalizedText(text, style: TextStyle(color: color, fontSize: 11)),
  );

  Widget _clientPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _toggleScan,
          icon: Icon(_scanning ? Icons.stop : Icons.radar),
          label: LocalizedText(_scanning ? '停止扫描' : '扫描附近设备'),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hint: LocalizedText('搜索名称或 MAC 地址'),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _search.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.clear),
                ),
        ),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: const LocalizedText('隐藏未命名'),
              selected: _hideUnnamed,
              onSelected: (value) => setState(() => _hideUnnamed = value),
            ),
            const SizedBox(width: 6),
            if (_section == 0)
              FilterChip(
                label: const LocalizedText('仅可连接'),
                selected: _onlyConnectable,
                onSelected: (value) => setState(() => _onlyConnectable = value),
              ),
            const SizedBox(width: 6),
            DropdownButton<String>(
              value: _sort,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'rssi', child: LocalizedText('按信号排序')),
                DropdownMenuItem(value: 'name', child: LocalizedText('按名称排序')),
                DropdownMenuItem(value: 'seen', child: LocalizedText('按最近出现')),
              ],
              onChanged: (value) => setState(() => _sort = value ?? 'rssi'),
            ),
          ],
        ),
      ),
      Row(
        children: [
          const LocalizedText('最低信号'),
          Expanded(
            child: Slider(
              value: _minRssi.toDouble(),
              min: -100,
              max: -30,
              divisions: 14,
              label: '$_minRssi dBm',
              onChanged: (value) => setState(() => _minRssi = value.round()),
            ),
          ),
          SizedBox(width: 64, child: LocalizedText('$_minRssi dBm')),
        ],
      ),
      Row(
        children: [
          LocalizedText(
            '${_visibleDevices.length} 台设备',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          if (_scanning) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            const LocalizedText('低延迟主动扫描'),
          ],
        ],
      ),
      const SizedBox(height: 8),
      if (_visibleDevices.isEmpty)
        Card(
          margin: EdgeInsets.zero,
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: LocalizedText('没有符合条件的设备。BLE 设备必须正在广播；经典蓝牙设备还必须处于可发现状态。'),
            ),
          ),
        )
      else
        ..._visibleDevices.map(_deviceTile),
      if (_section == 0 && _services.isNotEmpty) ...[
        const SizedBox(height: 14),
        Row(
          children: [
            LocalizedText(
              'GATT 服务树',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: _showGattTools,
              icon: const Icon(Icons.tune, size: 18),
              label: const LocalizedText('链路参数'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._services.map(_serviceTile),
      ],
    ],
  );

  Widget _serverPanel() => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          TextField(
            controller: _section == 0 ? _serviceId : _classicUuid,
            decoration: InputDecoration(
              labelText: _section == 0
                  ? 'GATT Service UUID'
                  : 'RFCOMM Service UUID',
            ),
          ),
          if (_section == 0) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _characteristicId,
              decoration: const InputDecoration(
                labelText: 'Characteristic UUID',
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _startServer,
              icon: const Icon(Icons.play_arrow),
              label: LocalizedText(
                _section == 0 ? '广播并启动 GATT Server' : '启动 RFCOMM Server',
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _stopServer,
              icon: const Icon(Icons.stop),
              label: const LocalizedText('停止服务'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _deviceTile(Map<Object?, Object?> device) {
    final address = device['address'] as String? ?? '';
    final name = _deviceName(device);
    final rssi = device['rssi'] as int?;
    final services = (device['services'] as List<Object?>? ?? const [])
        .map((value) => _shortUuid('$value'))
        .take(2)
        .toList();
    final history = _rssiHistory[address] ?? const <_RssiPoint>[];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDeviceDetails(device),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            children: [
              Row(
                children: [
                  _signalBadge(rssi),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: LocalizedText(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (device['bondState'] == 12)
                              _statusPill('已配对', Colors.blue),
                          ],
                        ),
                        LocalizedText(
                          '$address · ${rssi == null ? '无 RSSI' : '$rssi dBm'}',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _section == 0 && device['connectable'] == false
                        ? null
                        : () => _connect(device),
                    child: LocalizedText(
                      device['connectable'] == false ? '不可连接' : '连接',
                    ),
                  ),
                ],
              ),
              if (history.length > 1) ...[
                const SizedBox(height: 9),
                SizedBox(
                  height: 34,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _RssiSparklinePainter(
                      history.map((point) => point.value).toList(),
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
              if (services.isNotEmpty || device['manufacturerData'] is List)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      if (services.isNotEmpty)
                        Expanded(
                          child: LocalizedText(
                            '服务 ${services.join('、')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: () => _showDeviceDetails(device),
                        icon: const Icon(Icons.info_outline, size: 17),
                        label: const LocalizedText('广播详情'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signalBadge(int? rssi) {
    final color = rssi == null
        ? Colors.grey
        : rssi >= -60
        ? Colors.green
        : rssi >= -75
        ? Colors.orange
        : Colors.red;
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(Icons.bluetooth_searching, color: color),
    );
  }

  String _deviceName(Map<Object?, Object?> device) {
    final local = device['localName']?.toString().trim();
    final system = device['name']?.toString().trim();
    if (local?.isNotEmpty == true) return local!;
    if (system?.isNotEmpty == true) return system!;
    return '未命名设备';
  }

  Future<void> _showDeviceDetails(Map<Object?, Object?> device) async {
    final raw = device['rawBytes'];
    final rawBytes = raw is Uint8List ? raw : Uint8List(0);
    final manufacturer =
        (device['manufacturerData'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>();
    final serviceData = (device['serviceData'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        minChildSize: .45,
        maxChildSize: .94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            LocalizedText(
              _deviceName(device),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            SelectableText(
              device['address']?.toString() ?? '',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _detailChip('RSSI', '${device['rssi'] ?? '-'} dBm'),
                _detailChip('Tx Power', '${device['txPower'] ?? '-'} dBm'),
                _detailChip(
                  '连接',
                  _section == 1
                      ? _bondState(device['bondState'] as int?)
                      : (device['connectable'] == false ? '不可连接' : '可连接'),
                ),
                if (_section == 0)
                  _detailChip('Primary PHY', _phyName(device['primaryPhy'])),
                if (device['secondaryPhy'] != null)
                  _detailChip(
                    'Secondary PHY',
                    _phyName(device['secondaryPhy']),
                  ),
                if (device['periodicInterval'] != null)
                  _detailChip(
                    'Periodic',
                    '${((device['periodicInterval'] as int) * 1.25).toStringAsFixed(2)} ms',
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (_section == 0) ...[
              _detailSection(
                '广播服务 UUID',
                ((device['services'] as List<Object?>? ?? const []).isEmpty)
                    ? '无'
                    : (device['services'] as List<Object?>).join('\n'),
              ),
              for (final value in manufacturer)
                _detailSection(
                  'Manufacturer 0x${(value['id'] as int? ?? 0).toRadixString(16).padLeft(4, '0').toUpperCase()}',
                  _bytesHex(value['bytes']),
                ),
              for (final value in serviceData)
                _detailSection(
                  'Service Data · ${value['uuid']}',
                  _bytesHex(value['bytes']),
                ),
              _detailSection(
                'Advertising Flags',
                _advertisingFlags(device['advertiseFlags'] as int?),
              ),
              _detailSection(
                '原始广播包 · ${rawBytes.length} B',
                rawBytes.isEmpty
                    ? '设备或系统未返回原始数据'
                    : '${_bytesHex(rawBytes)}\n\n${_parseAdStructures(rawBytes)}',
              ),
            ] else
              _detailSection(
                '经典蓝牙信息',
                '设备类型: ${_classicType(device['type'] as int?)}\n'
                    '配对状态: ${_bondState(device['bondState'] as int?)}\n'
                    'RFCOMM UUID: ${_classicUuid.text}',
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _section == 0 && device['connectable'] == false
                  ? null
                  : () {
                      Navigator.pop(sheetContext);
                      _connect(device);
                    },
              icon: const Icon(Icons.link),
              label: LocalizedText(
                _section == 0 ? '连接并发现 GATT 服务' : '建立 RFCOMM 连接',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailChip(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(9),
    ),
    child: LocalizedText('$label  $value'),
  );

  Widget _detailSection(String title, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalizedText(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        SelectableText(value, style: const TextStyle(fontFamily: 'monospace')),
      ],
    ),
  );

  Widget _serviceTile(Map<Object?, Object?> service) {
    final id = service['uuid'] as String? ?? '';
    final characteristics =
        (service['characteristics'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: LocalizedText(
          '${_uuidName(id)} · ${_shortUuid(id)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: LocalizedText(id),
        children: [
          for (final characteristic in characteristics)
            _characteristicTile(id, characteristic),
        ],
      ),
    );
  }

  Widget _characteristicTile(
    String service,
    Map<Object?, Object?> characteristic,
  ) {
    final id = characteristic['uuid'] as String? ?? '';
    final properties = characteristic['properties'] as int? ?? 0;
    final canRead = properties & 0x02 != 0;
    final canWrite = properties & (0x08 | 0x04) != 0;
    final canNotify = properties & (0x10 | 0x20) != 0;
    final notifying = _notifyEnabled.contains(id);
    final descriptors =
        (characteristic['descriptors'] as List<Object?>? ?? const []);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: LocalizedText('${_uuidName(id)} · ${_shortUuid(id)}'),
      subtitle: LocalizedText(
        [
          if (canRead) 'READ',
          if (canWrite) 'WRITE',
          if (canNotify) 'NOTIFY',
          if (descriptors.isNotEmpty) '${descriptors.length} descriptor',
        ].join(' · '),
      ),
      trailing: Wrap(
        spacing: 0,
        children: [
          if (canRead)
            IconButton(
              onPressed: () => _service.readBle(service, id),
              icon: const Icon(Icons.download),
              tooltip: context.tr('读取'),
            ),
          if (canWrite)
            IconButton(
              onPressed: () => _writeCharacteristic(service, id),
              icon: const Icon(Icons.upload),
              tooltip: context.tr('写入'),
            ),
          if (canNotify)
            IconButton(
              onPressed: () async {
                final next = !notifying;
                await _service.notifyBle(service, id, next);
                if (mounted) {
                  setState(() {
                    if (next) {
                      _notifyEnabled.add(id);
                    } else {
                      _notifyEnabled.remove(id);
                    }
                  });
                }
                _message('${next ? '已订阅' : '已取消'} ${_shortUuid(id)}');
              },
              icon: Icon(
                notifying
                    ? Icons.notifications_active
                    : Icons.notifications_none,
              ),
              tooltip: notifying ? '取消通知' : '订阅通知/指示',
            ),
        ],
      ),
    );
  }

  Widget _sendPanel() => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          TextField(
            controller: _payload,
            minLines: 2,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: context.tr(_hex ? 'Hex 数据' : '文本数据'),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hex,
            onChanged: (value) => setState(() => _hex = value),
            title: const LocalizedText('Hex 模式'),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _section == 1 && _connectedAddress != null
                  ? _sendClassic
                  : (_section == 0 && _server ? _sendBleServer : null),
              icon: const Icon(Icons.send),
              label: LocalizedText(
                _section == 0
                    ? (_server
                          ? '向已连接 Central 发送 Notify'
                          : 'BLE 请在 Characteristic 中选择写入')
                    : '发送 RFCOMM 数据',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _logTile(Map<Object?, Object?> event) {
    final bytes = event['bytes'];
    final data = bytes is Uint8List ? bytes : Uint8List(0);
    final decoded = data.isEmpty
        ? (event['message']?.toString() ?? event['state']?.toString() ?? '')
        : utf8.decode(data, allowMalformed: true);
    final content = data.isEmpty
        ? decoded
        : '$decoded\n${data.map((v) => v.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase()}';
    final milliseconds = event['time'] as int?;
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        dense: true,
        onTap: () => _showPayload(event, decoded, data, milliseconds),
        title: LocalizedText(
          '${event['type']} · ${event['direction'] ?? event['scope'] ?? ''}',
        ),
        subtitle: SelectableText(
          content,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (milliseconds != null)
              LocalizedText(
                DateFormat(
                  'HH:mm:ss.SSS',
                ).format(DateTime.fromMillisecondsSinceEpoch(milliseconds)),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Future<void> _showPayload(
    Map<Object?, Object?> event,
    String decoded,
    Uint8List data,
    int? milliseconds,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LocalizedText(
                '${event['type'] ?? '蓝牙数据'} · ${event['direction'] ?? event['scope'] ?? ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StructuredDataViewer(
                  payload: StructuredPayload(
                    rawText: decoded,
                    rawBytes: data.isEmpty ? null : data,
                    source: event['type']?.toString(),
                    direction: (event['direction'] ?? event['scope'])
                        ?.toString(),
                    timestamp: milliseconds == null
                        ? null
                        : DateTime.fromMillisecondsSinceEpoch(milliseconds),
                    metadata: {
                      for (final entry in event.entries)
                        if (entry.key != 'bytes' && entry.key != 'message')
                          entry.key.toString(): entry.value,
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _toggleScan() async {
    if (Platform.isWindows || Platform.isLinux) {
      _message('桌面 BT/BLE 原生适配器尚未接入，当前版本不会返回虚假扫描结果。');
      return;
    }
    try {
      if (_scanning) {
        _scanWatchdog?.cancel();
        _section == 0
            ? await _service.stopBleScan()
            : await _service.stopClassicScan();
      } else {
        await _initialize();
        if (_scanIssue != null) {
          _message(_scanIssue!);
          return;
        }
        _devices.removeWhere(
          (_, device) => device['bonded'] != true && device['bondState'] != 12,
        );
        _rssiHistory.clear();
        _scanStartedAt = DateTime.now();
        _section == 0
            ? await _service.startBleScan()
            : await _service.startClassicScan();
        _scanWatchdog?.cancel();
        _scanWatchdog = Timer(const Duration(seconds: 6), () {
          final startedAt = _scanStartedAt?.millisecondsSinceEpoch ?? 0;
          final receivedAdvertisement = _devices.values.any(
            (device) => (device['seenAt'] as int? ?? 0) >= startedAt,
          );
          if (mounted && _scanning && !receivedAdvertisement) {
            setState(() {
              _scanIssue = _section == 0
                  ? '暂未收到新的 BLE 广播；已配对设备仍显示在列表中。请确认目标设备正在广播，或切换到经典蓝牙查看。'
                  : '暂未发现新的经典蓝牙设备；已配对设备仍显示在列表中，其他设备需开启“可被发现”模式。';
            });
          }
        });
      }
      if (mounted) setState(() => _scanning = !_scanning);
    } on Object catch (error) {
      _message('$error');
    }
  }

  Future<void> _connect(Map<Object?, Object?> device) async {
    final address = device['address'] as String?;
    if (address == null) return;
    try {
      if (_section == 0) {
        await _service.stopBleScan();
        await _service.connectBle(address);
      } else {
        await _service.stopClassicScan();
        await _service.connectClassic(address, _classicUuid.text.trim());
      }
      setState(() {
        _connectedAddress = address;
        _scanning = false;
        _connectionState = '正在连接 $address';
      });
    } on Object catch (error) {
      _message('$error');
    }
  }

  Future<void> _startServer() async {
    try {
      if (_section == 0) {
        final apiLevel = _status['apiLevel'] as int? ?? 31;
        if (apiLevel >= 31) {
          final permission = await Permission.bluetoothAdvertise.request();
          if (!permission.isGranted) {
            _message('需要“附近设备/蓝牙广播”权限才能启动 BLE 外设服务');
            return;
          }
        }
        await _service.startBleServer(
          _serviceId.text.trim(),
          _characteristicId.text.trim(),
        );
      } else {
        await _service.startClassicServer(
          'ProtoDeck RFCOMM',
          _classicUuid.text.trim(),
        );
      }
      setState(() => _connectionState = '服务端运行中');
    } on Object catch (error) {
      _message('$error');
    }
  }

  Future<void> _stopServer() async {
    _section == 0
        ? await _service.stopBleServer()
        : await _service.stopClassic();
    if (mounted) setState(() => _connectionState = '已停止');
  }

  Future<void> _sendClassic() async {
    try {
      await _service.sendClassic(
        SocketDebugService.parsePayload(_payload.text, hex: _hex),
      );
    } on Object catch (error) {
      _message('$error');
    }
  }

  Future<void> _sendBleServer() async {
    try {
      final clients = await _service.notifyBleServer(
        SocketDebugService.parsePayload(_payload.text, hex: _hex),
      );
      _message('已向 $clients 个 Central 发送 Notify');
    } on Object catch (error) {
      _message('$error');
    }
  }

  Future<void> _writeCharacteristic(
    String service,
    String characteristic,
  ) async {
    final controller = TextEditingController(text: _payload.text);
    var hex = _hex;
    var response = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: LocalizedText('写入 ${_shortUuid(characteristic)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: controller, minLines: 2, maxLines: 6),
              SwitchListTile(
                value: hex,
                onChanged: (v) => setDialogState(() => hex = v),
                title: const LocalizedText('Hex'),
              ),
              SwitchListTile(
                value: response,
                onChanged: (v) => setDialogState(() => response = v),
                title: const LocalizedText('Write with response'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LocalizedText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedText('写入'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      try {
        await _service.writeBle(
          service,
          characteristic,
          SocketDebugService.parsePayload(controller.text, hex: hex),
          withResponse: response,
        );
      } on Object catch (error) {
        _message('$error');
      }
    }
    controller.dispose();
  }

  Future<void> _poll() async {
    try {
      for (var index = 0; index < 20; index++) {
        final event = await _service.pollEvent();
        if (event == null) break;
        _handleEvent(event);
      }
    } on Object {
      // Native channel can briefly disappear during Activity teardown.
    }
  }

  void _handleEvent(Map<Object?, Object?> event) {
    if (!mounted) return;
    setState(() {
      final type = event['type'];
      if (type == 'bleDevice' || type == 'classicDevice') {
        final address = event['address'] as String?;
        if (address != null) {
          final previous = _devices[address] ?? const <Object?, Object?>{};
          _devices[address] = {...previous, ...event};
          final rssi = event['rssi'] as int?;
          if (rssi != null) {
            final history = _rssiHistory.putIfAbsent(address, () => []);
            history.add(_RssiPoint(DateTime.now(), rssi));
            if (history.length > 60) history.removeAt(0);
          }
          _scanIssue = null;
        }
      } else if (type == 'bleServices') {
        _services = (event['services'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .toList(growable: false);
      } else if (type == 'bleConnection' || type == 'classicConnection') {
        _connectionState = event['state']?.toString() ?? '未知';
        _connectedAddress = event['peer'] as String? ?? _connectedAddress;
      } else if (type == 'bleScan' || type == 'classicScan') {
        if (event['state'] == 'finished' || event['state'] == 'stopped')
          _scanning = false;
      }
      if (type != 'bleDevice' && type != 'classicDevice') {
        _logs.insert(0, event);
        if (_logs.length > 300) _logs.removeLast();
      }
    });
  }

  Future<void> _showGattTools() async {
    final mtu = TextEditingController(text: '247');
    var priority = 1;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            0,
            18,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                'BLE 链路参数',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: mtu,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        label: LocalizedText('请求 ATT MTU（23～517）'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () async {
                      final value = int.tryParse(mtu.text);
                      if (value != null) await _service.requestMtu(value);
                    },
                    child: const LocalizedText('请求'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: priority,
                items: const [
                  DropdownMenuItem(value: 0, child: LocalizedText('Balanced')),
                  DropdownMenuItem(
                    value: 1,
                    child: LocalizedText('High performance'),
                  ),
                  DropdownMenuItem(value: 2, child: LocalizedText('Low power')),
                ],
                onChanged: (value) =>
                    setSheetState(() => priority = value ?? 1),
                decoration: const InputDecoration(
                  label: LocalizedText('连接优先级'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _service.readRemoteRssi,
                      icon: const Icon(Icons.network_cell),
                      label: const LocalizedText('读取远端 RSSI'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _service.setConnectionPriority(priority),
                      icon: const Icon(Icons.speed),
                      label: const LocalizedText('应用优先级'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    mtu.dispose();
  }

  String _bytesHex(Object? value) {
    final bytes = value is Uint8List
        ? value
        : value is List<int>
        ? Uint8List.fromList(value)
        : Uint8List(0);
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ')
        .toUpperCase();
  }

  String _phyName(Object? value) => switch (value) {
    1 => 'LE 1M',
    2 => 'LE 2M',
    3 => 'LE Coded',
    _ => '未知',
  };

  String _bondState(int? value) => switch (value) {
    12 => '已配对',
    11 => '配对中',
    _ => '未配对',
  };

  String _classicType(int? value) => switch (value) {
    1 => 'Classic (BR/EDR)',
    2 => 'BLE',
    3 => 'Dual Mode',
    _ => '未知',
  };

  String _advertisingFlags(int? flags) {
    if (flags == null || flags < 0) return '未提供';
    return [
      '0x${flags.toRadixString(16).padLeft(2, '0').toUpperCase()}',
      if (flags & 0x01 != 0) 'LE Limited Discoverable',
      if (flags & 0x02 != 0) 'LE General Discoverable',
      if (flags & 0x04 != 0) 'BR/EDR Not Supported',
      if (flags & 0x08 != 0) 'Simultaneous LE/BR Controller',
      if (flags & 0x10 != 0) 'Simultaneous LE/BR Host',
    ].join(' · ');
  }

  String _parseAdStructures(Uint8List bytes) {
    const names = <int, String>{
      0x01: 'Flags',
      0x02: 'Incomplete 16-bit UUIDs',
      0x03: 'Complete 16-bit UUIDs',
      0x06: 'Incomplete 128-bit UUIDs',
      0x07: 'Complete 128-bit UUIDs',
      0x08: 'Short Local Name',
      0x09: 'Complete Local Name',
      0x0A: 'Tx Power',
      0x16: 'Service Data 16-bit',
      0x19: 'Appearance',
      0x20: 'Service Data 32-bit',
      0x21: 'Service Data 128-bit',
      0xFF: 'Manufacturer Specific',
    };
    final rows = <String>[];
    var offset = 0;
    while (offset < bytes.length) {
      final length = bytes[offset];
      if (length == 0) break;
      if (offset + length >= bytes.length) {
        rows.add('0x${offset.toRadixString(16).padLeft(2, '0')}: 截断的 AD 结构');
        break;
      }
      final type = bytes[offset + 1];
      final data = bytes.sublist(offset + 2, offset + 1 + length);
      rows.add(
        'AD 0x${type.toRadixString(16).padLeft(2, '0').toUpperCase()} '
        '${names[type] ?? 'Unknown'} · ${_bytesHex(data)}',
      );
      offset += length + 1;
    }
    return rows.isEmpty ? '未解析到 AD Structure' : rows.join('\n');
  }

  String _shortUuid(String value) {
    final normalized = value.toUpperCase();
    if (normalized.endsWith('-0000-1000-8000-00805F9B34FB')) {
      return '0x${normalized.substring(4, 8)}';
    }
    return normalized;
  }

  String _uuidName(String value) {
    final short = _shortUuid(value).toUpperCase();
    return const {
          '0X1800': 'Generic Access',
          '0X1801': 'Generic Attribute',
          '0X180A': 'Device Information',
          '0X180D': 'Heart Rate',
          '0X180F': 'Battery Service',
          '0X1812': 'Human Interface Device',
          '0X181A': 'Environmental Sensing',
          '0X2A00': 'Device Name',
          '0X2A01': 'Appearance',
          '0X2A05': 'Service Changed',
          '0X2A19': 'Battery Level',
          '0X2A24': 'Model Number',
          '0X2A25': 'Serial Number',
          '0X2A29': 'Manufacturer Name',
          '0X2A37': 'Heart Rate Measurement',
          '6E400001-B5A3-F393-E0A9-E50E24DCCA9E': 'Nordic UART Service',
          '6E400002-B5A3-F393-E0A9-E50E24DCCA9E': 'Nordic UART RX',
          '6E400003-B5A3-F393-E0A9-E50E24DCCA9E': 'Nordic UART TX',
        }[short] ??
        '自定义 UUID';
  }

  void _message(String value) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText(value)));
  }
}

class _RssiPoint {
  const _RssiPoint(this.time, this.value);
  final DateTime time;
  final int value;
}

class _RssiSparklinePainter extends CustomPainter {
  const _RssiSparklinePainter(this.values, this.color);

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final grid = Paint()
      ..color = color.withValues(alpha: .10)
      ..strokeWidth = 1;
    for (var index = 1; index < 3; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final normalized = ((values[index].clamp(-100, -30) + 100) / 70);
      final y = size.height - normalized * size.height;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RssiSparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
