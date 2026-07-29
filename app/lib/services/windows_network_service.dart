import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Windows implementation for the native capabilities that Android exposes
/// through `nettools/native`.
///
/// It intentionally invokes fixed Windows system tools without a shell. User
/// input is always passed as an individual process argument. This keeps the
/// desktop build useful without coupling the shared Flutter UI to Win32 APIs.
class WindowsNetworkBridge {
  WindowsNetworkBridge({WindowsProcessRunner? runner})
    : _runner = runner ?? const WindowsProcessRunner();

  static final instance = WindowsNetworkBridge();

  final WindowsProcessRunner _runner;
  final Stopwatch _uptime = Stopwatch()..start();
  Map<Object?, Object?>? _networkContextCache;
  DateTime? _networkContextCachedAt;
  Future<Map<Object?, Object?>>? _networkContextRequest;
  Process? _traceProcess;
  Process? _iperfProcess;
  final List<String> _iperfEvents = [];
  bool _iperfRunning = false;

  Future<Map<Object?, Object?>> getNetworkContext() async {
    final cachedAt = _networkContextCachedAt;
    final cached = _networkContextCache;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(seconds: 3)) {
      return Map<Object?, Object?>.of(cached);
    }
    final pending = _networkContextRequest;
    if (pending != null) return Map<Object?, Object?>.of(await pending);

    final request = _loadNetworkContext();
    _networkContextRequest = request;
    try {
      final value = await request;
      _networkContextCache = Map<Object?, Object?>.of(value);
      _networkContextCachedAt = DateTime.now();
      return Map<Object?, Object?>.of(value);
    } finally {
      if (identical(_networkContextRequest, request)) {
        _networkContextRequest = null;
      }
    }
  }

  Future<Map<Object?, Object?>> _loadNetworkContext() async {
    // PowerShell adapter discovery and netsh WLAN discovery are independent.
    // Running them concurrently materially reduces the first dashboard load.
    final results = await Future.wait<Object?>([
      _powershellJson(_networkContextScript),
      _currentWifi(),
    ]);
    final map = _objectMap(results[0]);
    final wifi = results[1];
    if (wifi is Map<String, Object?>) map['wifi'] = wifi;
    return map;
  }

  Future<Map<Object?, Object?>> scanWifiSnapshot() async {
    final result = await _runner.run('netsh.exe', const [
      'wlan',
      'show',
      'networks',
      'mode=bssid',
    ], timeout: const Duration(seconds: 8));
    if (result.exitCode != 0) {
      throw StateError(
        'Windows WLAN 查询失败：${_firstUsefulLine(result.stderr, result.stdout)}',
      );
    }
    final now = DateTime.now();
    final accessPoints = parseWifiScan(result.stdout, now: now);
    return {
      'accessPoints': accessPoints,
      // netsh exposes the WLAN service cache and does not guarantee that this
      // invocation initiated a new radio scan.
      'fresh': false,
      'requested': false,
      'status': 'windows_system_cache',
      'collectedAtMs': now.millisecondsSinceEpoch,
      'newestResultAgeMs': null,
      'supports24Ghz': accessPoints.any(
        (row) => (_asInt(row['frequency'])) < 3000,
      ),
      'supports5Ghz': accessPoints.any(
        (row) =>
            (_asInt(row['frequency'])) >= 4900 &&
            (_asInt(row['frequency'])) < 5925,
      ),
      'supports6Ghz': accessPoints.any(
        (row) => (_asInt(row['frequency'])) >= 5925,
      ),
      'usableChannels': const <Object?>[],
    };
  }

  Future<Map<Object?, Object?>> connectWifi({required String ssid}) async {
    final normalized = ssid.trim();
    if (normalized.isEmpty) throw const FormatException('SSID is required');
    final result = await _runner.run('netsh.exe', [
      'wlan',
      'connect',
      'name=$normalized',
      'ssid=$normalized',
    ], timeout: const Duration(seconds: 12));
    if (result.exitCode != 0) {
      throw StateError(
        'Windows could not connect to the saved Wi-Fi profile: '
        '${_firstUsefulLine(result.stderr, result.stdout)}',
      );
    }
    return {
      'status': 'connection_requested',
      'systemUiOpened': false,
      'message': result.stdout.trim(),
    };
  }

  Future<Map<Object?, Object?>> getTrafficSnapshot() async {
    final value = await _powershellJson(_trafficSnapshotScript);
    final map = _objectMap(value);
    final rawConnections = _objectList(map['connections']);
    map['connections'] = [
      for (final row in rawConnections)
        {
          ...row,
          'applicationProtocol': _applicationProtocol(
            _asInt(row['remotePort']),
            fallbackPort: _asInt(row['localPort']),
          ),
        },
    ];
    map['timestampMs'] = DateTime.now().millisecondsSinceEpoch;
    map['elapsedRealtimeMs'] = _uptime.elapsedMilliseconds;
    map['mobileRxBytes'] = null;
    map['mobileTxBytes'] = null;
    map['appRxBytes'] = null;
    map['appTxBytes'] = null;
    map['connectionVisibility'] = 'system';
    map['visibilityDetail'] =
        'Windows Get-NetAdapterStatistics / Get-NetTCPConnection / Get-NetUDPEndpoint';
    return map;
  }

  Future<Map<Object?, Object?>> runPing({
    required String host,
    required int count,
    required int timeoutMs,
    required int packetSize,
    bool? ipv6,
  }) async {
    final arguments = <String>[
      if (ipv6 == true) '-6' else if (ipv6 == false) '-4',
      '-n',
      '$count',
      '-w',
      '$timeoutMs',
      '-l',
      '$packetSize',
      host,
    ];
    final result = await _runner.run(
      'ping.exe',
      arguments,
      timeout: Duration(
        milliseconds: (count * timeoutMs).clamp(3000, 120000) + 3000,
      ),
    );
    return {
      'exitCode': result.exitCode,
      'output': normalizeWindowsPing(result.stdout, expectedCount: count),
      'command': 'ping.exe ${arguments.join(' ')}',
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
        '-n',
        '1',
        '-w',
        '$timeoutMs',
        if (!ipv6) '-f',
        '-l',
        '$payload',
        host,
      ];
      final result = await _runner.run(
        'ping.exe',
        arguments,
        timeout: Duration(milliseconds: timeoutMs + 2500),
      );
      watch.stop();
      final normalized = normalizeWindowsPing(result.stdout, expectedCount: 1);
      final success = normalized.contains('icmp_seq=1');
      attempts.add({
        'mtu': mtu,
        'payload': payload,
        'success': success,
        'elapsedMs': watch.elapsedMicroseconds / 1000,
        'output': _truncate(result.stdout.trim(), 800),
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
    required bool resolveHostnames,
  }) async {
    if (_traceProcess != null) throw StateError('已有路由追踪正在运行');
    final arguments = <String>[
      if (!resolveHostnames) '-d',
      '-h',
      '$maxHops',
      '-w',
      '$timeoutMs',
      host,
    ];
    final process = await _runner.start('tracert.exe', arguments);
    _traceProcess = process;
    try {
      final stdoutFuture = process.stdout
          .transform(systemEncoding.decoder)
          .join();
      final stderrFuture = process.stderr
          .transform(systemEncoding.decoder)
          .join();
      final exitCode = await process.exitCode.timeout(
        Duration(milliseconds: maxHops * timeoutMs * 3 + 15000),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      final output = await stdoutFuture;
      final error = await stderrFuture;
      final rows = parseTraceroute(output);
      if (rows.isEmpty && exitCode != 0) {
        throw StateError(
          'Windows tracert 失败：${_firstUsefulLine(error, output)}',
        );
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
        '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}iperf3.exe',
      );
      final executable = bundled.existsSync() ? bundled.path : 'iperf3.exe';
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
      final combined = '${output.toString()}${errors.toString()}';
      return jsonEncode({
        'ok': exitCode == 0,
        'exitCode': exitCode,
        'output': combined,
      });
    } on ProcessException catch (error) {
      final message = '内置 iperf3.exe 不可用，系统 PATH 中也未找到可执行文件：${error.message}';
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
        final addresses = _objectList(context['addresses']);
        final gateways = _stringList(context['gateways']);
        yield {
          'sequence': ++sequence,
          'timestampMs': DateTime.now().millisecondsSinceEpoch,
          'type': sequence == 1 ? 'snapshot' : 'changed',
          'connected': context['connected'] == true,
          'isDefault': true,
          'transports': _stringList(context['transports']),
          'validated': context['validated'] == true,
          'captivePortal': false,
          'partialConnectivity': false,
          'metered': context['metered'] == true,
          'interfaceName': context['interfaceName'],
          'mtu': context['mtu'],
          'addresses': addresses,
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

  Future<Object?> _powershellJson(String script) async {
    final result = await _runner.run('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ], timeout: const Duration(seconds: 12));
    if (result.exitCode != 0) {
      throw StateError(
        'Windows 网络接口查询失败：${_firstUsefulLine(result.stderr, result.stdout)}',
      );
    }
    final text = result.stdout.trim();
    if (text.isEmpty) throw StateError('Windows 网络接口查询没有返回数据');
    try {
      return jsonDecode(text);
    } on FormatException catch (error) {
      throw StateError('Windows 网络接口返回无法解析：${error.message}');
    }
  }

  Future<Map<String, Object?>?> _currentWifi() async {
    try {
      final result = await _runner.run('netsh.exe', const [
        'wlan',
        'show',
        'interfaces',
      ], timeout: const Duration(seconds: 6));
      if (result.exitCode != 0) return null;
      return parseCurrentWifi(result.stdout);
    } on Object {
      return null;
    }
  }

  static Map<String, Object?>? parseCurrentWifi(String output) {
    final values = <String, String>{};
    for (final raw in output.split(RegExp(r'\r?\n'))) {
      final separator = raw.indexOf(':');
      if (separator < 0) continue;
      final key = raw.substring(0, separator).trim().toLowerCase();
      final value = raw.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) values[key] = value;
    }
    String? byKey(bool Function(String key) match) {
      for (final entry in values.entries) {
        if (match(entry.key)) return entry.value;
      }
      return null;
    }

    final ssid = byKey((key) => key == 'ssid');
    if (ssid == null || ssid.isEmpty) return null;
    final bssid = byKey((key) => key == 'bssid');
    final signalText = byKey(
      (key) => key.contains('signal') || key.contains('信号'),
    );
    final signal = int.tryParse(signalText?.replaceAll('%', '') ?? '');
    final rssi = signal == null ? null : (signal / 2 - 100).round();
    final channel = int.tryParse(
      byKey(
            (key) =>
                key.contains('channel') ||
                key.contains('频道') ||
                key.contains('信道'),
          ) ??
          '',
    );
    final band = byKey((key) => key.contains('band') || key.contains('频段'));
    final frequency = _channelFrequency(channel, band: band);
    final rx = _numberFrom(
      byKey((key) => key.contains('receive rate') || key.contains('接收速率')),
    );
    final tx = _numberFrom(
      byKey((key) => key.contains('transmit rate') || key.contains('传输速率')),
    );
    final standard = byKey(
      (key) => key.contains('radio type') || key.contains('无线电类型'),
    );
    return {
      'ssid': ssid,
      'bssid': bssid,
      'rssi': rssi,
      'signalLevel': signal == null ? null : ((signal / 25).ceil()).clamp(1, 4),
      'frequency': frequency,
      'channel': channel,
      'linkSpeedMbps': tx ?? rx,
      'rxLinkSpeedMbps': rx,
      'txLinkSpeedMbps': tx,
      'standard': standard,
    };
  }

  static List<Map<String, Object?>> parseWifiScan(
    String output, {
    DateTime? now,
  }) {
    final rows = <Map<String, Object?>>[];
    String ssid = '';
    String security = '';
    Map<String, Object?>? current;
    void commit() {
      final row = current;
      if (row == null || (row['bssid'] as String?)?.isEmpty != false) return;
      final signal = row.remove('_signal') as int?;
      row['ssid'] = ssid;
      row['security'] = security;
      row['securityTypes'] = security.isEmpty ? const <String>[] : [security];
      row['rssi'] = signal == null ? -127 : (signal / 2 - 100).round();
      row['signalLevel'] = signal == null
          ? 0
          : ((signal / 25).ceil()).clamp(1, 4);
      final channel = row['channel'] as int?;
      row['frequency'] = _channelFrequency(channel);
      row['channelWidth'] = '系统未提供';
      row['timestampMicros'] = (now ?? DateTime.now()).microsecondsSinceEpoch;
      rows.add(row);
    }

    for (final raw in output.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      final ssidMatch = RegExp(
        r'^SSID\s+\d+\s*:\s*(.*)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (ssidMatch != null) {
        commit();
        current = null;
        ssid = ssidMatch.group(1)?.trim() ?? '';
        security = '';
        continue;
      }
      final bssidMatch = RegExp(
        r'^BSSID\s+\d+\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (bssidMatch != null) {
        commit();
        current = {'bssid': bssidMatch.group(1)!.trim().toUpperCase()};
        continue;
      }
      final separator = line.indexOf(':');
      if (separator < 0) continue;
      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      if (key.contains('authentication') ||
          key.contains('身份验证') ||
          key.contains('认证')) {
        security = value;
      } else if (current != null &&
          (key.contains('signal') || key.contains('信号'))) {
        current['_signal'] = int.tryParse(value.replaceAll('%', ''));
      } else if (current != null &&
          (key.contains('channel') ||
              key.contains('频道') ||
              key.contains('信道'))) {
        current['channel'] = int.tryParse(value) ?? 0;
      } else if (current != null &&
          (key.contains('radio type') || key.contains('无线电类型'))) {
        current['standard'] = value;
      }
    }
    commit();
    final deduplicated = <String, Map<String, Object?>>{};
    for (final row in rows) {
      deduplicated[row['bssid'] as String] = row;
    }
    return deduplicated.values.toList(growable: false);
  }

  static String normalizeWindowsPing(
    String output, {
    required int expectedCount,
  }) {
    final lines = <String>[];
    var sequence = 1;
    final addressPattern = RegExp(
      r'((?:\d{1,3}\.){3}\d{1,3}|(?:[0-9a-f]{0,4}:){2,}[0-9a-f:%]+)',
      caseSensitive: false,
    );
    final timePattern = RegExp(
      r'(?:time|时间)\s*[=<]\s*(\d+(?:\.\d+)?)\s*ms',
      caseSensitive: false,
    );
    final ttlPattern = RegExp(r'ttl\s*=\s*(\d+)', caseSensitive: false);
    for (final raw in output.split(RegExp(r'\r?\n'))) {
      final time = timePattern.firstMatch(raw);
      final ttl = ttlPattern.firstMatch(raw);
      final address = addressPattern.firstMatch(raw);
      if (time == null || ttl == null || address == null) continue;
      lines.add(
        'From ${address.group(1)}: icmp_seq=$sequence ttl=${ttl.group(1)} '
        'time=${time.group(1)} ms',
      );
      sequence++;
      if (sequence > expectedCount) break;
    }
    return lines.join('\n');
  }

  static List<Map<Object?, Object?>> parseTraceroute(String output) {
    final rows = <Map<Object?, Object?>>[];
    final hopPattern = RegExp(r'^\s*(\d+)\s+(.+)$');
    final timePattern = RegExp(r'<?(\d+(?:\.\d+)?)\s*ms', caseSensitive: false);
    final ipv4 = RegExp(r'(?:\d{1,3}\.){3}\d{1,3}');
    final bracketAddress = RegExp(r'\[([^\]]+)\]\s*$');
    for (final raw in output.split(RegExp(r'\r?\n'))) {
      final hopMatch = hopPattern.firstMatch(raw);
      if (hopMatch == null) continue;
      final hop = int.tryParse(hopMatch.group(1)!);
      if (hop == null || hop < 1) continue;
      final body = hopMatch.group(2)!;
      final times = timePattern
          .allMatches(body)
          .map<double?>((match) => double.tryParse(match.group(1)!))
          .toList(growable: true);
      while (times.length < 3) times.add(null);
      final bracket = bracketAddress.firstMatch(body);
      final address =
          bracket?.group(1) ?? ipv4.allMatches(body).lastOrNull?.group(0);
      String? hostname;
      if (bracket != null) {
        final prefix = body.substring(0, bracket.start).trim();
        final tokens = prefix.split(RegExp(r'\s+'));
        if (tokens.isNotEmpty) hostname = tokens.last;
      }
      rows.add({
        'hop': hop,
        'address': address,
        'hostname': hostname,
        'elapsedMs': times.whereType<double>().firstOrNull ?? 0.0,
        'samplesMs': times.take(3).toList(growable: false),
        'reached': false,
        'timeout': address == null,
        'raw': raw.trim(),
      });
    }
    return rows;
  }

  static int? _channelFrequency(int? channel, {String? band}) {
    if (channel == null || channel <= 0) return null;
    if (band?.contains('6') == true) return 5950 + channel * 5;
    if (channel == 14) return 2484;
    if (channel <= 13) return 2407 + channel * 5;
    return 5000 + channel * 5;
  }

  static int? _numberFrom(String? value) => value == null
      ? null
      : double.tryParse(
          RegExp(r'\d+(?:\.\d+)?').firstMatch(value)?.group(0) ?? '',
        )?.round();

  static String _applicationProtocol(int port, {required int fallbackPort}) {
    final value = port == 0 ? fallbackPort : port;
    return const {
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
        }[value] ??
        'Unknown';
  }

  static String _truncate(String value, int maximum) =>
      value.length <= maximum ? value : '${value.substring(0, maximum)}…';

  static String _firstUsefulLine(String first, String second) => [first, second]
      .expand((value) => value.split(RegExp(r'\r?\n')))
      .map((value) => value.trim())
      .firstWhere((value) => value.isNotEmpty, orElse: () => '未知错误');

  static Map<Object?, Object?> _objectMap(Object? value) {
    if (value is Map) return Map<Object?, Object?>.from(value);
    return <Object?, Object?>{};
  }

  static List<Map<Object?, Object?>> _objectList(Object? value) {
    final rows = value is List
        ? value
        : value == null
        ? const []
        : [value];
    return rows
        .whereType<Map>()
        .map((row) => Map<Object?, Object?>.from(row))
        .toList(growable: false);
  }

  static List<String> _stringList(Object? value) {
    final rows = value is List
        ? value
        : value == null
        ? const []
        : [value];
    return rows.map((row) => '$row').toList(growable: false);
  }

  static int _asInt(Object? value) => switch (value) {
    int number => number,
    num number => number.toInt(),
    _ => int.tryParse('$value') ?? 0,
  };

  static const _networkContextScript = r'''
$configs = @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.NetAdapter.Status -eq 'Up' })
$config = $configs | Where-Object { $_.IPv4DefaultGateway -or $_.IPv6DefaultGateway } | Select-Object -First 1
if (-not $config) { $config = $configs | Select-Object -First 1 }
if (-not $config) {
  [pscustomobject]@{ connected=$false; interfaceName=$null; transports=@(); validated=$false; captivePortal=$false; partialConnectivity=$false; metered=$false; addresses=@(); dnsServers=@(); gateways=@(); lanAddresses=@(); lanGateways=@(); adapters=@(); mtu=0 } | ConvertTo-Json -Compress -Depth 7
  exit
}
$index = $config.InterfaceIndex
$adapter = Get-NetAdapter -InterfaceIndex $index -ErrorAction SilentlyContinue
$profile = Get-NetConnectionProfile -InterfaceIndex $index -ErrorAction SilentlyContinue
$addresses = @(Get-NetIPAddress -InterfaceIndex $index -ErrorAction SilentlyContinue | Where-Object { $_.AddressState -eq 'Preferred' -and $_.IPAddress -notlike '127.*' -and $_.IPAddress -ne '::1' } | ForEach-Object { [pscustomobject]@{ address=$_.IPAddress; prefixLength=[int]$_.PrefixLength; family=$_.AddressFamily.ToString() } })
$dns = @(Get-DnsClientServerAddress -InterfaceIndex $index -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
$gateways = @()
if ($config.IPv4DefaultGateway) { $gateways += $config.IPv4DefaultGateway.NextHop }
if ($config.IPv6DefaultGateway) { $gateways += $config.IPv6DefaultGateway.NextHop }
$label = "$($adapter.Name) $($adapter.InterfaceDescription)"
$transport = 'ethernet'
if ($label -match 'Wi-?Fi|Wireless|WLAN|802\.11') { $transport = 'wifi' }
if ($label -match 'VPN|WireGuard|TAP|TUN|PPP') { $transport = 'vpn' }
$internet = $false
if ($profile) { $internet = ("$($profile.IPv4Connectivity)" -match 'Internet') -or ("$($profile.IPv6Connectivity)" -match 'Internet') }
$mtuRow = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
$mtu = 0
if ($mtuRow) { $mtu = [int]$mtuRow.NlMtu }
$adapters = @($configs | ForEach-Object {
  $itemConfig = $_
  $itemIndex = [int]$itemConfig.InterfaceIndex
  $itemAdapter = Get-NetAdapter -InterfaceIndex $itemIndex -ErrorAction SilentlyContinue
  $itemAddresses = @(Get-NetIPAddress -InterfaceIndex $itemIndex -ErrorAction SilentlyContinue | Where-Object { $_.AddressState -eq 'Preferred' -and $_.IPAddress -notlike '127.*' -and $_.IPAddress -ne '::1' } | ForEach-Object { [pscustomobject]@{ address=$_.IPAddress; prefixLength=[int]$_.PrefixLength; family=$_.AddressFamily.ToString() } })
  $itemDns = @(Get-DnsClientServerAddress -InterfaceIndex $itemIndex -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
  $itemGateways = @()
  if ($itemConfig.IPv4DefaultGateway) { $itemGateways += $itemConfig.IPv4DefaultGateway.NextHop }
  if ($itemConfig.IPv6DefaultGateway) { $itemGateways += $itemConfig.IPv6DefaultGateway.NextHop }
  $itemLabel = "$($itemAdapter.Name) $($itemAdapter.InterfaceDescription)"
  $itemTransport = 'ethernet'
  if ($itemLabel -match 'Wi-?Fi|Wireless|WLAN|802\.11') { $itemTransport = 'wifi' }
  if ($itemLabel -match 'VPN|WireGuard|TAP|TUN|PPP') { $itemTransport = 'vpn' }
  $itemMtuRow = Get-NetIPInterface -InterfaceIndex $itemIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
  [pscustomobject]@{
    interfaceIndex=$itemIndex
    name="$($itemConfig.InterfaceAlias)"
    description="$($itemAdapter.InterfaceDescription)"
    status="$($itemAdapter.Status)"
    transport=$itemTransport
    isDefault=($itemIndex -eq $index)
    macAddress="$($itemAdapter.MacAddress)"
    linkSpeed="$($itemAdapter.LinkSpeed)"
    mtu=if ($itemMtuRow) { [int]$itemMtuRow.NlMtu } else { 0 }
    addresses=$itemAddresses
    dnsServers=$itemDns
    gateways=$itemGateways
  }
})
[pscustomobject]@{
  connected=$true
  interfaceName=$config.InterfaceAlias
  transports=@($transport)
  validated=$internet
  captivePortal=$false
  partialConnectivity=$false
  metered=$false
  addresses=$addresses
  dnsServers=$dns
  gateways=$gateways
  lanAddresses=$addresses
  lanGateways=$gateways
  mtu=$mtu
  adapters=$adapters
} | ConvertTo-Json -Compress -Depth 7
''';

  static const _trafficSnapshotScript = r'''
$stats = @(Get-NetAdapterStatistics -ErrorAction Stop | Where-Object { $_.ReceivedBytes -ge 0 })
$processInfo = @{}
Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $processInfo[[int]$_.Id] = [pscustomobject]@{ name=$_.ProcessName; path=$_.Path } }
$tcp = @(Get-NetTCPConnection -ErrorAction SilentlyContinue | Select-Object -First 800 | ForEach-Object { $pidValue=[int]$_.OwningProcess; $owner=$processInfo[$pidValue]; [pscustomobject]@{ protocol='TCP'; ipVersion=if ($_.RemoteAddress -like '*:*') { 6 } else { 4 }; localAddress=$_.LocalAddress; localPort=[int]$_.LocalPort; remoteAddress=$_.RemoteAddress; remotePort=[int]$_.RemotePort; state="$($_.State)"; uid=$null; pid=$pidValue; processName=$owner.name; executablePath=$owner.path } })
$udp = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Select-Object -First 200 | ForEach-Object { $pidValue=[int]$_.OwningProcess; $owner=$processInfo[$pidValue]; [pscustomobject]@{ protocol='UDP'; ipVersion=if ($_.LocalAddress -like '*:*') { 6 } else { 4 }; localAddress=$_.LocalAddress; localPort=[int]$_.LocalPort; remoteAddress=''; remotePort=0; state='Listening'; uid=$null; pid=$pidValue; processName=$owner.name; executablePath=$owner.path } })
[pscustomobject]@{
  totalRxBytes=[long](($stats | Measure-Object -Property ReceivedBytes -Sum).Sum)
  totalTxBytes=[long](($stats | Measure-Object -Property SentBytes -Sum).Sum)
  connections=@($tcp + $udp)
} | ConvertTo-Json -Compress -Depth 5
''';
}

class WindowsProcessRunner {
  const WindowsProcessRunner();

  Future<WindowsProcessResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    // Individual Windows diagnostics carry their own native time limits
    // (ping/tracert) or are bounded PowerShell queries. Avoid a Dart-side
    // timeout timer so a disposed page never leaves an orphaned timer behind.
    final result = await Process.run(
      executable,
      arguments,
      runInShell: false,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );
    return WindowsProcessResult(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  }

  Future<Process> start(String executable, List<String> arguments) =>
      Process.start(executable, arguments, runInShell: false);
}

class WindowsProcessResult {
  const WindowsProcessResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

extension _FirstOrNullWindows<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}
