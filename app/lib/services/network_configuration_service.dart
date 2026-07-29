import 'dart:convert';
import 'dart:io';

import '../data/app_database.dart';
import '../models/network_configuration.dart';
import 'network_command_runner.dart';
import 'network_configuration_inspector.dart';

class NetworkConfigurationTemplateRepository {
  NetworkConfigurationTemplateRepository(this._database);

  static const _settingKey = 'network.configuration.templates.v1';
  final AppDatabase _database;

  Future<List<NetworkConfigurationTemplate>> load() async {
    final values = decodeNetworkTemplates(
      await _database.getSetting(_settingKey),
    );
    return [...values]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> save(NetworkConfigurationTemplate template) async {
    template.validate();
    final values = await load();
    final next = [
      template,
      ...values.where((value) => value.id != template.id),
    ];
    await saveAll(next);
  }

  Future<void> saveAll(List<NetworkConfigurationTemplate> templates) async {
    for (final template in templates) {
      template.validate();
    }
    final unique = <String, NetworkConfigurationTemplate>{};
    for (final value in templates) {
      unique[value.id] = value;
    }
    await _database.putSetting(
      _settingKey,
      encodeNetworkTemplates(unique.values.toList()),
    );
  }

  Future<void> delete(String id) async {
    final values = await load();
    await saveAll(values.where((value) => value.id != id).toList());
  }

  Future<int> importJson(String source) async {
    final imported = decodeNetworkTemplates(source);
    if (imported.isEmpty) throw const FormatException('文件中没有有效的网络配置模板');
    final current = await load();
    await saveAll([...current, ...imported]);
    return imported.length;
  }

  Future<String> exportJson() async => const JsonEncoder.withIndent(
    '  ',
  ).convert([for (final value in await load()) value.toJson()]);
}

class NetworkConfigurationRestorePointRepository {
  NetworkConfigurationRestorePointRepository(this._database);

  static const _settingKey = 'network.configuration.last_restore_point.v1';
  final AppDatabase _database;

  Future<NetworkConfigurationRestorePoint?> load() async =>
      decodeNetworkRestorePoint(await _database.getSetting(_settingKey));

  Future<void> save(NetworkConfigurationRestorePoint value) =>
      _database.putSetting(_settingKey, encodeNetworkRestorePoint(value));

  Future<void> clear() => _database.putSetting(_settingKey, '');
}

class NetworkConfigurationService {
  NetworkConfigurationService({
    NetworkCommandRunner? runner,
    NetworkConfigurationInspector? inspector,
  }) : _runner = runner ?? const NetworkCommandRunner(),
       inspector = inspector ?? NetworkConfigurationInspector(runner: runner);

  final NetworkCommandRunner _runner;
  final NetworkConfigurationInspector inspector;

  bool get supported => Platform.isWindows || Platform.isLinux;

  Future<NetworkConfigurationApplyResult> apply(
    NetworkConfigurationTemplate template, {
    NetworkConfigurationRestorePoint? restorePoint,
  }) async {
    template.validate();
    if (Platform.isAndroid) {
      return const NetworkConfigurationApplyResult(
        success: false,
        message: 'Android 仅提供只读网络信息，不支持修改系统 IP 配置',
      );
    }
    final point =
        restorePoint ??
        await inspector.captureRestorePoint(template.interfaceName);
    final platformResult = Platform.isWindows
        ? await _applyWindows(template)
        : Platform.isLinux
        ? await _applyLinux(template, point)
        : const NetworkConfigurationApplyResult(
            success: false,
            message: '当前平台不支持修改网络配置',
          );
    if (!platformResult.success) return platformResult;
    if (platformResult.verification.isNotEmpty) return platformResult;
    try {
      final verification = await inspector.verify(template);
      return platformResult.copyWith(verification: verification);
    } on Object catch (error) {
      return platformResult.copyWith(
        verification: [
          NetworkConfigurationVerificationItem(
            label: '实际配置重读',
            expected: '可成功读取',
            actual: '暂时失败：$error',
            matches: false,
            requiredForWrite: false,
            detail: '配置写入已成功，重读失败不触发回滚',
          ),
        ],
      );
    }
  }

  Future<NetworkConfigurationApplyResult> restore(
    NetworkConfigurationRestorePoint point,
  ) async {
    if (point.platform != Platform.operatingSystem) {
      return NetworkConfigurationApplyResult(
        success: false,
        message: '该恢复点来自 ${point.platform}，不能在 ${Platform.operatingSystem} 上应用',
      );
    }
    if (Platform.isWindows) return _restoreWindows(point);
    if (Platform.isLinux) {
      final restored = await _restoreLinuxPoint(point);
      return NetworkConfigurationApplyResult(
        success: restored,
        message: restored ? '已恢复上一次修改前的网络配置' : '恢复上一次配置失败',
      );
    }
    return const NetworkConfigurationApplyResult(
      success: false,
      message: '当前平台不支持恢复网络配置',
    );
  }

  Future<NetworkConfigurationApplyResult> _applyWindows(
    NetworkConfigurationTemplate template,
  ) async {
    final payload = base64Encode(utf8.encode(jsonEncode(template.toJson())));
    final script = _windowsApplyScript.replaceAll('__PAYLOAD__', payload);
    final result = await _runPowerShell(script, const Duration(seconds: 50));
    final parsed = _decodeResult(result.stdout);
    if (parsed != null) return NetworkConfigurationApplyResult.fromJson(parsed);
    final detail = _firstLine(result);
    return NetworkConfigurationApplyResult(
      success: false,
      message: detail,
      requiresElevation: _needsElevation(detail),
    );
  }

  Future<NetworkConfigurationApplyResult> _applyLinux(
    NetworkConfigurationTemplate template,
    NetworkConfigurationRestorePoint point,
  ) async {
    final raw = point.raw;
    final connection = raw['connection']?.toString();
    if (connection == null || connection.isEmpty || connection == '--') {
      return NetworkConfigurationApplyResult(
        success: false,
        message: 'NetworkManager 未找到接口 ${template.interfaceName} 的可修改连接',
      );
    }
    final modify = <String>[
      'connection',
      'modify',
      connection,
      if (template.mode == NetworkAddressMode.dhcp) ...[
        'ipv4.method',
        'auto',
        'ipv4.addresses',
        '',
        'ipv4.gateway',
        '',
        'ipv4.dns',
        '',
        'ipv4.ignore-auto-dns',
        'no',
      ] else ...[
        'ipv4.method',
        'manual',
        'ipv4.addresses',
        '${template.address}/${template.prefixLength}',
        'ipv4.gateway',
        template.gateway ?? '',
        'ipv4.dns',
        template.dnsServers.join(','),
        'ipv4.ignore-auto-dns',
        template.dnsServers.isEmpty ? 'no' : 'yes',
      ],
      if (template.interfaceMetric != null) ...[
        'ipv4.route-metric',
        '${template.interfaceMetric}',
      ],
      'ipv4.routes',
      _nmcliRoutes(template.staticRoutes),
    ];
    final changed = await _runner.run(
      'nmcli',
      modify,
      timeout: const Duration(seconds: 15),
    );
    if (changed.exitCode != 0) {
      final rollback = await _restoreLinuxPoint(point);
      return NetworkConfigurationApplyResult(
        success: false,
        message: _firstLine(changed),
        requiresElevation: _needsElevation(
          '${changed.stderr}\n${changed.stdout}',
        ),
        rollbackAttempted: true,
        rollbackSucceeded: rollback,
      );
    }
    final activated = await _runner.run('nmcli', [
      'connection',
      'up',
      connection,
      'ifname',
      template.interfaceName,
    ], timeout: const Duration(seconds: 35));
    if (activated.exitCode != 0) {
      final rollback = await _restoreLinuxPoint(point);
      return NetworkConfigurationApplyResult(
        success: false,
        message: '重新激活连接失败：${_firstLine(activated)}',
        requiresElevation: _needsElevation(
          '${activated.stderr}\n${activated.stdout}',
        ),
        rollbackAttempted: true,
        rollbackSucceeded: rollback,
      );
    }
    List<NetworkConfigurationVerificationItem> verification;
    try {
      verification = await inspector.verify(template);
    } on Object catch (error) {
      return NetworkConfigurationApplyResult(
        success: true,
        message: template.mode == NetworkAddressMode.dhcp
            ? '已写入 DHCP 配置；地址获取和联网状态将单独检测'
            : '静态 IPv4、DNS 和路由参数已写入',
        verification: [
          NetworkConfigurationVerificationItem(
            label: '实际配置重读',
            expected: '可成功读取',
            actual: '暂时失败：$error',
            matches: false,
            requiredForWrite: false,
            detail: '配置写入已成功，重读失败不触发回滚',
          ),
        ],
      );
    }
    final critical = verification.where((value) => value.requiredForWrite);
    if (critical.any((value) => !value.matches)) {
      final rollback = await _restoreLinuxPoint(point);
      return NetworkConfigurationApplyResult(
        success: false,
        message: '配置写入后的实际参数与目标不一致',
        rollbackAttempted: true,
        rollbackSucceeded: rollback,
        verification: verification,
      );
    }
    return NetworkConfigurationApplyResult(
      success: true,
      message: template.mode == NetworkAddressMode.dhcp
          ? '已写入 DHCP 配置；地址获取和联网状态将单独检测'
          : '静态 IPv4、DNS 和路由参数已写入',
      observedAddress: verification
          .where((value) => value.label == 'IPv4 地址')
          .firstOrNull
          ?.actual,
      verification: verification,
    );
  }

  Future<bool> _restoreLinuxPoint(
    NetworkConfigurationRestorePoint point,
  ) async {
    final raw = point.raw;
    final connection = raw['connection']?.toString();
    if (connection == null || connection.isEmpty || connection == '--')
      return false;
    final modified = await _runner.run('nmcli', [
      'connection',
      'modify',
      connection,
      'ipv4.method',
      raw['method']?.toString() ?? 'auto',
      'ipv4.addresses',
      raw['addresses']?.toString() ?? '',
      'ipv4.gateway',
      raw['gateway']?.toString() ?? '',
      'ipv4.dns',
      raw['dns']?.toString() ?? '',
      'ipv4.ignore-auto-dns',
      raw['ignoreAutoDns']?.toString() ?? 'no',
      'ipv4.route-metric',
      raw['routeMetric']?.toString() ?? '',
      'ipv4.routes',
      raw['routes']?.toString() ?? '',
    ], timeout: const Duration(seconds: 15));
    if (modified.exitCode != 0) return false;
    final activated = await _runner.run('nmcli', [
      'connection',
      'up',
      connection,
      'ifname',
      point.interfaceName,
    ], timeout: const Duration(seconds: 35));
    return activated.exitCode == 0;
  }

  Future<NetworkConfigurationApplyResult> _restoreWindows(
    NetworkConfigurationRestorePoint point,
  ) async {
    final payload = base64Encode(
      utf8.encode(
        jsonEncode({'interfaceName': point.interfaceName, 'raw': point.raw}),
      ),
    );
    final script = _windowsRestoreScript.replaceAll('__PAYLOAD__', payload);
    final result = await _runPowerShell(script, const Duration(seconds: 45));
    final parsed = _decodeResult(result.stdout);
    if (parsed != null) return NetworkConfigurationApplyResult.fromJson(parsed);
    final detail = _firstLine(result);
    return NetworkConfigurationApplyResult(
      success: false,
      message: detail,
      requiresElevation: _needsElevation(detail),
    );
  }

  Future<NetworkCommandResult> _runPowerShell(
    String script,
    Duration timeout,
  ) => _runner.run('powershell.exe', [
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    script,
  ], timeout: timeout);

  static String _nmcliRoutes(List<NetworkStaticRoute> routes) => routes
      .map((value) => '${value.destination} ${value.gateway} ${value.metric}')
      .join(',');

  static Map<String, Object?>? _decodeResult(String value) {
    final lines = value.trim().split(RegExp(r'\r?\n')).reversed;
    for (final line in lines) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          return decoded.map<String, Object?>(
            (key, value) => MapEntry('$key', value),
          );
        }
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  static bool _needsElevation(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('access is denied') ||
        normalized.contains('administrator') ||
        normalized.contains('privilege') ||
        normalized.contains('not authorized') ||
        normalized.contains('permission denied') ||
        normalized.contains('拒绝访问');
  }

  static String _firstLine(NetworkCommandResult result) =>
      '${result.stderr}\n${result.stdout}'
          .split(RegExp(r'\r?\n'))
          .map((value) => value.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '未知错误');

  static const _windowsApplyScript = r'''
$ErrorActionPreference = 'Stop'
$payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
$alias = [string]$payload.interfaceName
$beforeInterface = Get-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction Stop | Select-Object -First 1
$beforeAddresses = @(Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '127.*' } | ForEach-Object { [pscustomobject]@{ address="$($_.IPAddress)"; prefix=[int]$_.PrefixLength } })
$beforeDefaultRoutes = @(Get-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ destination='0.0.0.0/0'; gateway="$($_.NextHop)"; metric=[int]$_.RouteMetric } })
$beforeCustomRoutes = @(Get-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -ne '0.0.0.0/0' -and $_.NextHop -ne '0.0.0.0' } | ForEach-Object { [pscustomobject]@{ destination="$($_.DestinationPrefix)"; gateway="$($_.NextHop)"; metric=[int]$_.RouteMetric } })
$beforeDns = @(Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
$rollbackAttempted = $false
$rollbackSucceeded = $false
function Clear-ProtoDeckIPv4 {
  Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '127.*' } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  Get-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -ne '0.0.0.0' } | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
}
function Restore-ProtoDeckIPv4 {
  Clear-ProtoDeckIPv4
  Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -InterfaceMetric ([int]$beforeInterface.InterfaceMetric) -ErrorAction Stop
  if ("$($beforeInterface.Dhcp)" -eq 'Enabled') {
    Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop
    Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -ErrorAction Stop
  } else {
    Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
    $first = $true
    foreach ($item in $beforeAddresses) {
      $args = @{ InterfaceAlias=$alias; AddressFamily='IPv4'; IPAddress=[string]$item.address; PrefixLength=[int]$item.prefix; ErrorAction='Stop' }
      if ($first -and $beforeDefaultRoutes.Count -gt 0) { $args.DefaultGateway = [string]$beforeDefaultRoutes[0].gateway }
      New-NetIPAddress @args | Out-Null
      $first = $false
    }
    if ($beforeDns.Count -gt 0) { Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses $beforeDns -ErrorAction Stop } else { Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -ErrorAction Stop }
    foreach ($route in $beforeCustomRoutes) { New-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -DestinationPrefix ([string]$route.destination) -NextHop ([string]$route.gateway) -RouteMetric ([int]$route.metric) -ErrorAction SilentlyContinue | Out-Null }
  }
}
try {
  Clear-ProtoDeckIPv4
  if ([string]$payload.mode -eq 'dhcp') {
    Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop
    Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -ErrorAction Stop
  } else {
    Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
    $addressArgs = @{ InterfaceAlias=$alias; AddressFamily='IPv4'; IPAddress=[string]$payload.address; PrefixLength=[int]$payload.prefixLength; ErrorAction='Stop' }
    if (-not [string]::IsNullOrWhiteSpace([string]$payload.gateway)) { $addressArgs.DefaultGateway = [string]$payload.gateway }
    New-NetIPAddress @addressArgs | Out-Null
    $dns = @($payload.dnsServers | ForEach-Object { [string]$_ })
    if ($dns.Count -gt 0) { Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses $dns -ErrorAction Stop } else { Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -ErrorAction Stop }
  }
  if ($null -ne $payload.interfaceMetric) { Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -InterfaceMetric ([int]$payload.interfaceMetric) -ErrorAction Stop }
  foreach ($route in @($payload.staticRoutes)) { New-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -DestinationPrefix ([string]$route.destination) -NextHop ([string]$route.gateway) -RouteMetric ([int]$route.metric) -ErrorAction Stop | Out-Null }
  Start-Sleep -Milliseconds 500
  $afterInterface = Get-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction Stop | Select-Object -First 1
  if ([string]$payload.mode -eq 'dhcp') {
    if ("$($afterInterface.Dhcp)" -ne 'Enabled') { throw 'DHCP state was not written' }
  } else {
    if ("$($afterInterface.Dhcp)" -ne 'Disabled') { throw 'Static IPv4 mode was not written' }
    $afterAddress = Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -IPAddress ([string]$payload.address) -ErrorAction SilentlyContinue | Where-Object { [int]$_.PrefixLength -eq [int]$payload.prefixLength } | Select-Object -First 1
    if (-not $afterAddress) { throw 'The requested IPv4 address or prefix was not observed' }
    if (-not [string]::IsNullOrWhiteSpace([string]$payload.gateway)) {
      $afterGateway = Get-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -eq [string]$payload.gateway } | Select-Object -First 1
      if (-not $afterGateway) { throw 'The requested default gateway was not observed' }
    }
    $wantedDns = @($payload.dnsServers | ForEach-Object { [string]$_ })
    if ($wantedDns.Count -gt 0) {
      $afterDns = @(Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction Stop | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
      foreach ($server in $wantedDns) { if ($afterDns -notcontains $server) { throw "DNS server $server was not observed" } }
    }
  }
  if ($null -ne $payload.interfaceMetric -and [int]$afterInterface.InterfaceMetric -ne [int]$payload.interfaceMetric) { throw 'Interface metric was not written' }
  foreach ($route in @($payload.staticRoutes)) {
    $found = Get-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -DestinationPrefix ([string]$route.destination) -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -eq [string]$route.gateway -and [int]$_.RouteMetric -eq [int]$route.metric } | Select-Object -First 1
    if (-not $found) { throw "Static route $($route.destination) was not written" }
  }
  $observed = Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -AddressState Preferred -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1 -ExpandProperty IPAddress
  [pscustomobject]@{ success=$true; message='Network configuration was written; connectivity is checked separately'; requiresElevation=$false; rollbackAttempted=$false; rollbackSucceeded=$false; observedAddress=$observed } | ConvertTo-Json -Compress
} catch {
  $message = $_.Exception.Message
  $requiresElevation = $message -match 'Access is denied|administrator|privilege|拒绝访问'
  try { $rollbackAttempted = $true; Restore-ProtoDeckIPv4; $rollbackSucceeded = $true } catch { $rollbackSucceeded = $false }
  [pscustomobject]@{ success=$false; message="$message"; requiresElevation=$requiresElevation; rollbackAttempted=$rollbackAttempted; rollbackSucceeded=$rollbackSucceeded; observedAddress=$null } | ConvertTo-Json -Compress
}
''';

  static const _windowsRestoreScript = r'''
$ErrorActionPreference = 'Stop'
$payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
$alias = [string]$payload.interfaceName
$raw = $payload.raw
try {
  Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '127.*' } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  Get-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -ne '0.0.0.0' } | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
  Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -InterfaceMetric ([int]$raw.interfaceMetric) -ErrorAction Stop
  if ([bool]$raw.dhcp) {
    Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop
    Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -ErrorAction Stop
  } else {
    Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
    $first = $true
    foreach ($item in @($raw.addresses)) {
      $args = @{ InterfaceAlias=$alias; AddressFamily='IPv4'; IPAddress=[string]$item.address; PrefixLength=[int]$item.prefix; ErrorAction='Stop' }
      if ($first -and @($raw.defaultRoutes).Count -gt 0) { $args.DefaultGateway = [string]$raw.defaultRoutes[0].gateway }
      New-NetIPAddress @args | Out-Null
      $first = $false
    }
    $dns = @($raw.dns | ForEach-Object { [string]$_ })
    if ($dns.Count -gt 0) { Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses $dns -ErrorAction Stop } else { Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -ErrorAction Stop }
    foreach ($route in @($raw.customRoutes)) { New-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -DestinationPrefix ([string]$route.destination) -NextHop ([string]$route.gateway) -RouteMetric ([int]$route.metric) -ErrorAction SilentlyContinue | Out-Null }
  }
  [pscustomobject]@{ success=$true; message='Previous network configuration restored'; requiresElevation=$false; rollbackAttempted=$false; rollbackSucceeded=$false; observedAddress=$null } | ConvertTo-Json -Compress
} catch {
  $message = $_.Exception.Message
  [pscustomobject]@{ success=$false; message="$message"; requiresElevation=($message -match 'Access is denied|administrator|privilege|拒绝访问'); rollbackAttempted=$false; rollbackSucceeded=$false; observedAddress=$null } | ConvertTo-Json -Compress
}
''';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
