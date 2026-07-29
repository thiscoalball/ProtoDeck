import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class LinuxNetworkBridge {
  LinuxNetworkBridge({LinuxProcessRunner? runner})
    : _runner = runner ?? const LinuxProcessRunner();

  static final instance = LinuxNetworkBridge();

  final LinuxProcessRunner _runner;
  final Stopwatch _uptime = Stopwatch()..start();
  Process? _traceProcess;
  Process? _iperfProcess;
  final List<String> _iperfEvents = [];
  bool _iperfRunning = false;

  Future<Map<Object?, Object?>> getNetworkContext() async {
    final addressesResult = await _runner.run('ip', const [
      '-j',
      'address',
      'show',
      'up',
    ], timeout: const Duration(seconds: 5));
    if (addressesResult.exitCode != 0) {
      throw StateError('读取 Linux 网卡失败：${addressesResult.stderr.trim()}');
    }
    final interfaces = _jsonRows(addressesResult.stdout);
    final routes = await _defaultRoutes();
    final preferredName = routes
        .map((route) => route['dev']?.toString())
        .whereType<String>()
        .firstOrNull;
    Map<String, Object?>? selected;
    if (preferredName != null) {
      selected = interfaces
          .where((row) => row['ifname'] == preferredName)
          .firstOrNull;
    }
    selected ??= interfaces.where(_isUsefulInterface).firstOrNull;
    if (selected == null) return _disconnectedContext();

    final interfaceName = selected['ifname']?.toString();
    final addressRows = _list(selected['addr_info'])
        .whereType<Map>()
        .where(
          (row) =>
              (row['family'] == 'inet' || row['family'] == 'inet6') &&
              row['scope'] != 'host',
        )
        .map(
          (row) => <String, Object?>{
            'address': row['local']?.toString() ?? '',
            'prefixLength': _asInt(row['prefixlen']),
            'family': row['family'] == 'inet6' ? 'IPv6' : 'IPv4',
          },
        )
        .where((row) => (row['address'] as String).isNotEmpty)
        .toList(growable: false);
    final gateways = routes
        .where((row) => row['dev'] == interfaceName)
        .map((row) => row['gateway']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final transport = _transportFor(interfaceName ?? '');
    final connectivity = await _networkManagerConnectivity();
    final wifi = transport == 'wifi' ? await _currentWifi() : null;
    return {
      'connected': addressRows.isNotEmpty,
      'interfaceName': interfaceName,
      'transports': [transport],
      'validated': connectivity == 'full',
      'captivePortal': connectivity == 'portal',
      'partialConnectivity': connectivity == 'limited',
      'metered': await _isMetered(interfaceName),
      'addresses': addressRows,
      'dnsServers': await _dnsServers(),
      'gateways': gateways,
      'lanAddresses': addressRows,
      'lanGateways': gateways,
      'mtu': _asInt(selected['mtu']),
      'wifi': ?wifi,
    };
  }

  Future<Map<Object?, Object?>> scanWifiSnapshot() async {
    final now = DateTime.now();
    final result = await _runner.run('nmcli', const [
      '-t',
      '-e',
      'no',
      '-s',
      '|',
      '-f',
      'IN-USE,SSID,BSSID,SIGNAL,FREQ,CHAN,RATE,SECURITY',
      'device',
      'wifi',
      'list',
      '--rescan',
      'yes',
    ], timeout: const Duration(seconds: 15));
    if (result.exitCode != 0) {
      throw StateError(
        'NetworkManager Wi-Fi 扫描失败：${_firstLine(result.stderr, result.stdout)}',
      );
    }
    final accessPoints = parseNmcliWifi(result.stdout, now: now);
    return {
      'accessPoints': accessPoints,
      'fresh': true,
      'requested': true,
      'status': 'linux_networkmanager',
      'collectedAtMs': now.millisecondsSinceEpoch,
      'newestResultAgeMs': 0,
      'supports24Ghz': accessPoints.any(
        (row) => _asInt(row['frequency']) < 3000,
      ),
      'supports5Ghz': accessPoints.any(
        (row) =>
            _asInt(row['frequency']) >= 4900 && _asInt(row['frequency']) < 5925,
      ),
      'supports6Ghz': accessPoints.any(
        (row) => _asInt(row['frequency']) >= 5925,
      ),
      'usableChannels': const <Object?>[],
    };
  }

  Future<Map<Object?, Object?>> connectWifi({
    required String ssid,
    String password = '',
    String? interfaceName,
    bool hidden = false,
  }) async {
    final normalized = ssid.trim();
    if (normalized.isEmpty) throw const FormatException('SSID is required');
    final arguments = <String>[
      'device',
      'wifi',
      'connect',
      normalized,
      if (password.isNotEmpty) ...['password', password],
      if (interfaceName?.trim().isNotEmpty == true) ...[
        'ifname',
        interfaceName!.trim(),
      ],
      if (hidden) ...['hidden', 'yes'],
    ];
    final result = await _runner.run(
      'nmcli',
      arguments,
      timeout: const Duration(seconds: 35),
    );
    if (result.exitCode != 0) {
      throw StateError(
        'NetworkManager could not connect to Wi-Fi: '
        '${_firstLine(result.stderr, result.stdout)}',
      );
    }
    return {
      'status': 'connection_requested',
      'systemUiOpened': false,
      'message': result.stdout.trim(),
    };
  }

  Future<Map<Object?, Object?>> getTrafficSnapshot() async {
    final counters = parseProcNetDev(
      await File('/proc/net/dev').readAsString(),
    );
    final connections = <Map<String, Object?>>[];
    for (final source in const [
      ('TCP', 4, '/proc/net/tcp'),
      ('TCP', 6, '/proc/net/tcp6'),
      ('UDP', 4, '/proc/net/udp'),
      ('UDP', 6, '/proc/net/udp6'),
    ]) {
      try {
        connections.addAll(
          parseProcConnections(
            await File(source.$3).readAsString(),
            protocol: source.$1,
            ipVersion: source.$2,
          ),
        );
      } on FileSystemException {
        // Some hardened distributions hide selected protocol tables.
      }
    }
    final owners = await _socketOwners(
      connections
          .map((row) => (row['inode'] as num?)?.toInt())
          .whereType<int>()
          .where((inode) => inode > 0)
          .toSet(),
    );
    for (final connection in connections) {
      final owner = owners[(connection['inode'] as num?)?.toInt()];
      if (owner == null) continue;
      connection
        ..['pid'] = owner.$1
        ..['processName'] = owner.$2
        ..['applicationLabel'] = owner.$2
        ..['executablePath'] = owner.$3;
    }
    return {
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
      'elapsedRealtimeMs': _uptime.elapsedMilliseconds,
      'totalRxBytes': counters.$1,
      'totalTxBytes': counters.$2,
      'mobileRxBytes': null,
      'mobileTxBytes': null,
      'appRxBytes': null,
      'appTxBytes': null,
      'connections': connections.take(1200).toList(growable: false),
      'connectionVisibility': 'system',
      'visibilityDetail': 'Linux /proc/net/dev 与 /proc/net/{tcp,udp}',
    };
  }

  Future<Map<Object?, Object?>> runPing({
    required String host,
    required int count,
    required int timeoutMs,
    required int intervalMs,
    required int packetSize,
    bool? ipv6,
  }) async {
    final arguments = <String>[
      if (ipv6 == true) '-6' else if (ipv6 == false) '-4',
      '-c',
      '$count',
      '-W',
      '${(timeoutMs / 1000).ceil().clamp(1, 60)}',
      '-i',
      (intervalMs / 1000).clamp(.1, 60).toStringAsFixed(3),
      '-s',
      '$packetSize',
      host,
    ];
    final result = await _runner.run(
      'ping',
      arguments,
      timeout: Duration(
        milliseconds: (count * (timeoutMs + intervalMs)).clamp(3000, 180000),
      ),
    );
    return {
      'exitCode': result.exitCode,
      'output': result.stdout,
      'command': 'ping ${arguments.join(' ')}',
    };
  }

  Future<Map<Object?, Object?>> probePathMtu({
    required String host,
    required int interfaceMtu,
    required bool ipv6,
    required int timeoutMs,
  }) async {
    final header = ipv6 ? 48 : 28;
    var low = ipv6 ? 1280 : 576;
    var high = interfaceMtu;
    int? best;
    var sawFailure = false;
    final attempts = <Map<String, Object?>>[];
    while (low <= high && attempts.length < 16) {
      final mtu = (low + high) ~/ 2;
      final payload = (mtu - header).clamp(0, 65500);
      final watch = Stopwatch()..start();
      final arguments = <String>[
        if (ipv6) '-6' else '-4',
        '-c',
        '1',
        '-W',
        '${(timeoutMs / 1000).ceil().clamp(1, 60)}',
        '-M',
        'do',
        '-s',
        '$payload',
        host,
      ];
      final result = await _runner.run(
        'ping',
        arguments,
        timeout: Duration(milliseconds: timeoutMs + 2500),
      );
      watch.stop();
      final success =
          result.exitCode == 0 && result.stdout.contains('icmp_seq=');
      attempts.add({
        'mtu': mtu,
        'payload': payload,
        'success': success,
        'elapsedMs': watch.elapsedMicroseconds / 1000,
        'output': _truncate('${result.stdout}${result.stderr}'.trim(), 800),
      });
      if (success) {
        best = mtu;
        low = mtu + 1;
      } else {
        sawFailure = true;
        high = mtu - 1;
      }
    }
    return {
      'host': host,
      'ipv6': ipv6,
      'interfaceMtu': interfaceMtu,
      'pathMtu': best,
      'attempts': attempts,
      'conclusive': best != null && sawFailure,
    };
  }

  Future<List<Map<Object?, Object?>>> runTraceroute({
    required String host,
    required int maxHops,
    required int timeoutMs,
    required int probes,
    required bool resolveHostnames,
  }) async {
    if (_traceProcess != null) throw StateError('已有路由追踪正在运行');
    final arguments = <String>[
      if (!resolveHostnames) '-n',
      '-m',
      '$maxHops',
      '-q',
      '$probes',
      '-w',
      (timeoutMs / 1000).clamp(.5, 10).toStringAsFixed(2),
      host,
    ];
    Process process;
    try {
      process = await _runner.start('traceroute', arguments);
    } on ProcessException {
      process = await _runner.start('tracepath', [
        '-n',
        '-m',
        '$maxHops',
        host,
      ]);
    }
    _traceProcess = process;
    try {
      final stdoutFuture = process.stdout
          .transform(systemEncoding.decoder)
          .join();
      final stderrFuture = process.stderr
          .transform(systemEncoding.decoder)
          .join();
      final exitCode = await process.exitCode.timeout(
        Duration(milliseconds: maxHops * timeoutMs * probes + 15000),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      final output = await stdoutFuture;
      final error = await stderrFuture;
      final rows = parseTraceroute(output, probes: probes);
      if (rows.isEmpty && exitCode != 0) {
        throw StateError('Linux traceroute 失败：${_firstLine(error, output)}');
      }
      if (rows.isNotEmpty && exitCode == 0) rows.last['reached'] = true;
      return rows;
    } finally {
      _traceProcess = null;
    }
  }

  Future<void> cancelTraceroute() async {
    _traceProcess?.kill();
    _traceProcess = null;
  }

  Future<String> runIperf(List<String> arguments) async {
    if (_iperfRunning) {
      return jsonEncode({
        'ok': false,
        'exitCode': -1,
        'output': '已有 iPerf3 会话正在运行',
      });
    }
    _iperfEvents.clear();
    final effective = <String>[
      ...arguments,
      if (!arguments.contains('--json-stream')) '--json-stream',
      if (!arguments.contains('--forceflush')) '--forceflush',
    ];
    try {
      final bundled = File(
        '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}iperf3',
      );
      final executable = bundled.existsSync() ? bundled.path : 'iperf3';
      final process = await _runner.start(executable, effective);
      _iperfProcess = process;
      _iperfRunning = true;
      final output = StringBuffer();
      final errors = StringBuffer();
      final stdoutDone = process.stdout
          .transform(systemEncoding.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            output.writeln(line);
            if (line.trim().isNotEmpty) _iperfEvents.add(line);
          })
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(systemEncoding.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            errors.writeln(line);
            _iperfEvents.add(jsonEncode({'event': 'error', 'data': line}));
          })
          .asFuture<void>();
      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      return jsonEncode({
        'ok': exitCode == 0,
        'exitCode': exitCode,
        'output': '${output.toString()}${errors.toString()}',
      });
    } on ProcessException catch (error) {
      final message = '内置 iperf3 不可用，系统 PATH 中也未找到可执行文件：${error.message}';
      _iperfEvents.add(jsonEncode({'event': 'error', 'data': message}));
      return jsonEncode({'ok': false, 'exitCode': -1, 'output': message});
    } finally {
      _iperfRunning = false;
      _iperfProcess = null;
    }
  }

  Future<bool> stopIperf() async {
    final process = _iperfProcess;
    if (process == null) return false;
    process.kill();
    return true;
  }

  bool get isIperfRunning => _iperfRunning;

  String? pollIperfEvent() =>
      _iperfEvents.isEmpty ? null : _iperfEvents.removeAt(0);

  Stream<Map<Object?, Object?>> watchNetworkEvents({
    Duration interval = const Duration(seconds: 2),
  }) async* {
    String? previousSignature;
    var sequence = 0;
    while (true) {
      final context = await getNetworkContext();
      final signature = jsonEncode(context);
      if (signature != previousSignature) {
        previousSignature = signature;
        final gateways = _stringList(context['gateways']);
        yield {
          'sequence': ++sequence,
          'timestampMs': DateTime.now().millisecondsSinceEpoch,
          'type': sequence == 1 ? 'snapshot' : 'changed',
          'connected': context['connected'] == true,
          'isDefault': true,
          'transports': _stringList(context['transports']),
          'validated': context['validated'] == true,
          'captivePortal': context['captivePortal'] == true,
          'partialConnectivity': context['partialConnectivity'] == true,
          'metered': context['metered'] == true,
          'interfaceName': context['interfaceName'],
          'mtu': context['mtu'],
          'addresses': _list(context['addresses']),
          'dnsServers': _stringList(context['dnsServers']),
          'routes': [
            for (final gateway in gateways)
              {
                'destination': gateway.contains(':') ? '::/0' : '0.0.0.0/0',
                'gateway': gateway,
                'default': true,
              },
          ],
          if (context['wifi'] case final Map<Object?, Object?> wifi) ...{
            'ssid': wifi['ssid'],
            'bssid': wifi['bssid'],
            'rssi': wifi['rssi'],
            'frequency': wifi['frequency'],
            'linkSpeedMbps': wifi['linkSpeedMbps'],
          },
        };
      }
      await Future<void>.delayed(interval);
    }
  }

  Future<List<Map<String, Object?>>> _defaultRoutes() async {
    final rows = <Map<String, Object?>>[];
    for (final args in const [
      ['-j', 'route', 'show', 'default'],
      ['-j', '-6', 'route', 'show', 'default'],
    ]) {
      try {
        final result = await _runner.run(
          'ip',
          args,
          timeout: const Duration(seconds: 4),
        );
        if (result.exitCode == 0) rows.addAll(_jsonRows(result.stdout));
      } on Object {
        // IPv6 may be disabled.
      }
    }
    rows.sort((a, b) => _asInt(a['metric']).compareTo(_asInt(b['metric'])));
    return rows;
  }

  Future<String?> _networkManagerConnectivity() async {
    try {
      final result = await _runner.run('nmcli', const [
        '-t',
        '-f',
        'CONNECTIVITY',
        'general',
      ], timeout: const Duration(seconds: 4));
      if (result.exitCode == 0) return result.stdout.trim().toLowerCase();
    } on Object {}
    return null;
  }

  Future<bool> _isMetered(String? interfaceName) async {
    if (interfaceName == null) return false;
    try {
      final result = await _runner.run('nmcli', [
        '-t',
        '-f',
        'GENERAL.METERED',
        'device',
        'show',
        interfaceName,
      ], timeout: const Duration(seconds: 4));
      final value = result.stdout.toLowerCase();
      return value.contains(':yes') || value.contains(':guess-yes');
    } on Object {
      return false;
    }
  }

  Future<List<String>> _dnsServers() async {
    try {
      return await File('/etc/resolv.conf').readAsLines().then(
        (lines) => lines
            .map((line) => RegExp(r'^\s*nameserver\s+(\S+)').firstMatch(line))
            .whereType<RegExpMatch>()
            .map((match) => match.group(1)!)
            .toSet()
            .toList(growable: false),
      );
    } on FileSystemException {
      return const [];
    }
  }

  Future<Map<String, Object?>?> _currentWifi() async {
    try {
      final result = await _runner.run('nmcli', const [
        '-t',
        '-e',
        'no',
        '-s',
        '|',
        '-f',
        'IN-USE,SSID,BSSID,SIGNAL,FREQ,CHAN,RATE,SECURITY',
        'device',
        'wifi',
        'list',
        '--rescan',
        'no',
      ], timeout: const Duration(seconds: 6));
      if (result.exitCode != 0) return null;
      return parseNmcliWifi(
        result.stdout,
      ).where((row) => row['active'] == true).firstOrNull;
    } on Object {
      return null;
    }
  }

  static List<Map<String, Object?>> parseNmcliWifi(
    String output, {
    DateTime? now,
  }) {
    final rows = <Map<String, Object?>>[];
    for (final line in output.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;
      final fields = line.split('|');
      if (fields.length < 8) continue;
      final signal = int.tryParse(fields[3]);
      final frequency = int.tryParse(fields[4]);
      final channel = int.tryParse(fields[5]);
      final rate = double.tryParse(
        RegExp(r'\d+(?:\.\d+)?').firstMatch(fields[6])?.group(0) ?? '',
      );
      rows.add({
        'active': fields[0].trim() == '*',
        'ssid': fields[1],
        'bssid': fields[2].toUpperCase(),
        'rssi': signal == null ? -127 : (signal / 2 - 100).round(),
        'signalLevel': signal == null ? 0 : ((signal / 25).ceil()).clamp(1, 4),
        'frequency': frequency ?? 0,
        'channel': channel ?? 0,
        'channelWidth': '系统未提供',
        'security': fields[7],
        'securityTypes': fields[7].isEmpty ? const <String>[] : [fields[7]],
        'timestampMicros': (now ?? DateTime.now()).microsecondsSinceEpoch,
        'linkSpeedMbps': rate?.round(),
        'rxLinkSpeedMbps': null,
        'txLinkSpeedMbps': rate?.round(),
        'standard': null,
      });
    }
    final byBssid = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final key = row['bssid'] as String;
      if (key.isNotEmpty) byBssid[key] = row;
    }
    return byBssid.values.toList(growable: false);
  }

  static (int, int) parseProcNetDev(String source) {
    var rx = 0;
    var tx = 0;
    for (final line in source.split('\n')) {
      final separator = line.indexOf(':');
      if (separator < 0) continue;
      final name = line.substring(0, separator).trim();
      if (name.isEmpty || name == 'lo') continue;
      final fields = line.substring(separator + 1).trim().split(RegExp(r'\s+'));
      if (fields.length < 16) continue;
      rx += int.tryParse(fields[0]) ?? 0;
      tx += int.tryParse(fields[8]) ?? 0;
    }
    return (rx, tx);
  }

  static List<Map<String, Object?>> parseProcConnections(
    String source, {
    required String protocol,
    required int ipVersion,
  }) {
    final rows = <Map<String, Object?>>[];
    for (final line in source.split('\n').skip(1)) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 8) continue;
      final local = _decodeProcEndpoint(fields[1], ipVersion);
      final remote = _decodeProcEndpoint(fields[2], ipVersion);
      if (local == null || remote == null) continue;
      rows.add({
        'protocol': protocol,
        'ipVersion': ipVersion,
        'localAddress': local.$1,
        'localPort': local.$2,
        'remoteAddress': remote.$1,
        'remotePort': remote.$2,
        'state': protocol == 'TCP' ? _tcpState(fields[3]) : 'Listening',
        'applicationProtocol': _applicationProtocol(
          remote.$2 == 0 ? local.$2 : remote.$2,
        ),
        'uid': int.tryParse(fields[7]),
        'inode': fields.length > 9 ? int.tryParse(fields[9]) : null,
      });
    }
    return rows;
  }

  static Future<Map<int, (int, String, String?)>> _socketOwners(
    Set<int> requested,
  ) async {
    if (requested.isEmpty) return const {};
    final result = <int, (int, String, String?)>{};
    try {
      await for (final process in Directory('/proc').list(followLinks: false)) {
        if (result.length >= requested.length) break;
        final pid = int.tryParse(process.path.split('/').last);
        if (pid == null) continue;
        final fdDirectory = Directory('${process.path}/fd');
        if (!await fdDirectory.exists()) continue;
        String? processName;
        String? executablePath;
        try {
          processName = (await File(
            '${process.path}/comm',
          ).readAsString()).trim();
        } on FileSystemException {
          processName = null;
        }
        try {
          executablePath = await Link('${process.path}/exe').target();
        } on FileSystemException {
          executablePath = null;
        }
        try {
          await for (final descriptor in fdDirectory.list(followLinks: false)) {
            if (descriptor is! Link) continue;
            String target;
            try {
              target = await descriptor.target();
            } on FileSystemException {
              continue;
            }
            final match = RegExp(r'^socket:\[(\d+)\]$').firstMatch(target);
            final inode = int.tryParse(match?.group(1) ?? '');
            if (inode != null && requested.contains(inode)) {
              result[inode] = (
                pid,
                processName?.isNotEmpty == true ? processName! : 'PID $pid',
                executablePath,
              );
            }
          }
        } on FileSystemException {
          // Processes owned by another user can hide their descriptor table.
        }
      }
    } on FileSystemException {
      return result;
    }
    return result;
  }

  static (String, int)? _decodeProcEndpoint(String value, int version) {
    final separator = value.lastIndexOf(':');
    if (separator < 0) return null;
    final addressHex = value.substring(0, separator);
    final port = int.tryParse(value.substring(separator + 1), radix: 16);
    if (port == null) return null;
    try {
      if (version == 4) {
        final bytes = Uint8List.fromList([
          for (var index = 6; index >= 0; index -= 2)
            int.parse(addressHex.substring(index, index + 2), radix: 16),
        ]);
        return (InternetAddress.fromRawAddress(bytes).address, port);
      }
      final bytes = <int>[];
      for (var word = 0; word < 4; word++) {
        final offset = word * 8;
        for (var index = offset + 6; index >= offset; index -= 2) {
          bytes.add(
            int.parse(addressHex.substring(index, index + 2), radix: 16),
          );
        }
      }
      return (
        InternetAddress.fromRawAddress(Uint8List.fromList(bytes)).address,
        port,
      );
    } on Object {
      return null;
    }
  }

  static List<Map<Object?, Object?>> parseTraceroute(
    String output, {
    required int probes,
  }) {
    final rows = <Map<Object?, Object?>>[];
    final hopPattern = RegExp(r'^\s*(\d+)[?:]?\s+(.+)$');
    final timePattern = RegExp(r'(\d+(?:\.\d+)?)\s*ms', caseSensitive: false);
    final ipv4 = RegExp(r'(?:\d{1,3}\.){3}\d{1,3}');
    final parenthesized = RegExp(r'\(([^)]+)\)');
    for (final raw in output.split(RegExp(r'\r?\n'))) {
      final match = hopPattern.firstMatch(raw);
      if (match == null) continue;
      final hop = int.tryParse(match.group(1)!);
      if (hop == null || hop < 1) continue;
      final body = match.group(2)!;
      final samples = timePattern
          .allMatches(body)
          .map<double?>((item) => double.tryParse(item.group(1)!))
          .toList(growable: true);
      while (samples.length < probes) samples.add(null);
      final parenthesis = parenthesized.firstMatch(body);
      final address = parenthesis?.group(1) ?? ipv4.firstMatch(body)?.group(0);
      final hostname = parenthesis == null
          ? null
          : body
                .substring(0, parenthesis.start)
                .trim()
                .split(RegExp(r'\s+'))
                .last;
      rows.add({
        'hop': hop,
        'address': address,
        'hostname': hostname,
        'elapsedMs': samples.whereType<double>().firstOrNull ?? 0.0,
        'samplesMs': samples.take(probes).toList(growable: false),
        'reached': false,
        'timeout': address == null,
        'raw': raw.trim(),
      });
    }
    return rows;
  }

  static String _tcpState(String value) =>
      const {
        '01': 'Established',
        '02': 'SynSent',
        '03': 'SynReceived',
        '04': 'FinWait1',
        '05': 'FinWait2',
        '06': 'TimeWait',
        '07': 'Closed',
        '08': 'CloseWait',
        '09': 'LastAck',
        '0A': 'Listening',
        '0B': 'Closing',
      }[value.toUpperCase()] ??
      'Unknown';

  static String _applicationProtocol(int port) =>
      const {
        22: 'SSH',
        23: 'Telnet',
        53: 'DNS',
        67: 'DHCP',
        68: 'DHCP',
        80: 'HTTP',
        123: 'NTP',
        161: 'SNMP',
        162: 'SNMP Trap',
        443: 'HTTPS / QUIC',
        445: 'SMB',
        514: 'Syslog',
        1883: 'MQTT',
        8883: 'MQTTS',
        5201: 'iPerf3',
      }[port] ??
      'Unknown';

  static bool _isUsefulInterface(Map<String, Object?> row) {
    final name = row['ifname']?.toString() ?? '';
    return name != 'lo' && _list(row['addr_info']).isNotEmpty;
  }

  static String _transportFor(String name) {
    final value = name.toLowerCase();
    if (value.startsWith('wl')) return 'wifi';
    if (value.startsWith('ww') || value.startsWith('rmnet')) return 'cellular';
    if (value.startsWith('tun') ||
        value.startsWith('tap') ||
        value.startsWith('wg') ||
        value.startsWith('ppp')) {
      return 'vpn';
    }
    return 'ethernet';
  }

  static Map<Object?, Object?> _disconnectedContext() => {
    'connected': false,
    'interfaceName': null,
    'transports': const <String>[],
    'validated': false,
    'captivePortal': false,
    'partialConnectivity': false,
    'metered': false,
    'addresses': const <Object?>[],
    'dnsServers': const <String>[],
    'gateways': const <String>[],
    'lanAddresses': const <Object?>[],
    'lanGateways': const <String>[],
    'mtu': 0,
  };

  static List<Map<String, Object?>> _jsonRows(String value) {
    final decoded = jsonDecode(value);
    return _list(decoded)
        .whereType<Map>()
        .map(
          (row) =>
              row.map<String, Object?>((key, value) => MapEntry('$key', value)),
        )
        .toList(growable: false);
  }

  static List<Object?> _list(Object? value) => value is List
      ? value
      : value == null
      ? const []
      : [value];

  static List<String> _stringList(Object? value) =>
      _list(value).map((item) => '$item').toList(growable: false);

  static int _asInt(Object? value) => switch (value) {
    int number => number,
    num number => number.toInt(),
    _ => int.tryParse('$value') ?? 0,
  };

  static String _truncate(String value, int maximum) =>
      value.length <= maximum ? value : '${value.substring(0, maximum)}…';

  static String _firstLine(String first, String second) => [first, second]
      .expand((value) => value.split(RegExp(r'\r?\n')))
      .map((value) => value.trim())
      .firstWhere((value) => value.isNotEmpty, orElse: () => '未知错误');
}

class LinuxProcessRunner {
  const LinuxProcessRunner();

  static const _environment = {'LC_ALL': 'C', 'LANG': 'C'};

  Future<LinuxProcessResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    final timeoutValue = '${timeout.inMilliseconds}ms';
    final result = await Process.run(
      'timeout',
      ['--signal=KILL', timeoutValue, executable, ...arguments],
      runInShell: false,
      environment: _environment,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );
    if (result.exitCode == 124 || result.exitCode == 137) {
      throw TimeoutException('$executable 执行超时', timeout);
    }
    return LinuxProcessResult(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  }

  Future<Process> start(String executable, List<String> arguments) =>
      Process.start(
        executable,
        arguments,
        runInShell: false,
        environment: _environment,
      );
}

class LinuxProcessResult {
  const LinuxProcessResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

extension _FirstOrNullLinux<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
