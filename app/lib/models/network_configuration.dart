import 'dart:convert';
import 'dart:io';

enum NetworkAddressMode { dhcp, staticIpv4 }

enum NetworkInterfaceMatchMode { exactName, macAddress, defaultTransport }

enum NetworkDiagnosticKind { adapter, gateway, dns, internet }

enum NetworkCheckState { pending, running, passed, warning, notApplicable }

enum IpConflictState { notChecked, clear, suspected, inconclusive }

class NetworkStaticRoute {
  const NetworkStaticRoute({
    required this.destination,
    required this.gateway,
    this.metric = 100,
  });

  final String destination;
  final String gateway;
  final int metric;

  void validate() {
    final parts = destination.trim().split('/');
    final address = InternetAddress.tryParse(parts.first);
    final prefix = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (parts.length != 2 ||
        address?.type != InternetAddressType.IPv4 ||
        prefix == null ||
        prefix < 0 ||
        prefix > 32) {
      throw FormatException('静态路由目标不是有效的 IPv4 CIDR：$destination');
    }
    _requireIpv4(gateway, '静态路由网关');
    if (metric < 1 || metric > 9999) {
      throw const FormatException('路由 Metric 应为 1～9999');
    }
  }

  Map<String, Object?> toJson() => {
    'destination': destination,
    'gateway': gateway,
    'metric': metric,
  };

  factory NetworkStaticRoute.fromJson(Map<String, Object?> json) =>
      NetworkStaticRoute(
        destination: json['destination']?.toString() ?? '',
        gateway: json['gateway']?.toString() ?? '',
        metric: (json['metric'] as num?)?.toInt() ?? 100,
      );
}

class NetworkConfigurationTemplate {
  const NetworkConfigurationTemplate({
    required this.id,
    required this.name,
    required this.interfaceName,
    required this.mode,
    this.interfaceMatchMode = NetworkInterfaceMatchMode.exactName,
    this.interfaceMacAddress,
    this.interfaceTransport,
    this.address,
    this.prefixLength = 24,
    this.gateway,
    this.dnsServers = const [],
    this.interfaceMetric,
    this.staticRoutes = const [],
    this.diagnostics = const {
      NetworkDiagnosticKind.adapter,
      NetworkDiagnosticKind.gateway,
      NetworkDiagnosticKind.dns,
      NetworkDiagnosticKind.internet,
    },
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String interfaceName;
  final NetworkInterfaceMatchMode interfaceMatchMode;
  final String? interfaceMacAddress;
  final String? interfaceTransport;
  final NetworkAddressMode mode;
  final String? address;
  final int prefixLength;
  final String? gateway;
  final List<String> dnsServers;
  final int? interfaceMetric;
  final List<NetworkStaticRoute> staticRoutes;
  final Set<NetworkDiagnosticKind> diagnostics;
  final DateTime updatedAt;

  NetworkConfigurationTemplate copyWith({
    String? id,
    String? name,
    String? interfaceName,
    NetworkInterfaceMatchMode? interfaceMatchMode,
    String? interfaceMacAddress,
    String? interfaceTransport,
    NetworkAddressMode? mode,
    String? address,
    int? prefixLength,
    String? gateway,
    List<String>? dnsServers,
    int? interfaceMetric,
    bool clearInterfaceMetric = false,
    List<NetworkStaticRoute>? staticRoutes,
    Set<NetworkDiagnosticKind>? diagnostics,
    DateTime? updatedAt,
  }) => NetworkConfigurationTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    interfaceName: interfaceName ?? this.interfaceName,
    interfaceMatchMode: interfaceMatchMode ?? this.interfaceMatchMode,
    interfaceMacAddress: interfaceMacAddress ?? this.interfaceMacAddress,
    interfaceTransport: interfaceTransport ?? this.interfaceTransport,
    mode: mode ?? this.mode,
    address: address ?? this.address,
    prefixLength: prefixLength ?? this.prefixLength,
    gateway: gateway ?? this.gateway,
    dnsServers: dnsServers ?? this.dnsServers,
    interfaceMetric: clearInterfaceMetric
        ? null
        : interfaceMetric ?? this.interfaceMetric,
    staticRoutes: staticRoutes ?? this.staticRoutes,
    diagnostics: diagnostics ?? this.diagnostics,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  void validate() {
    if (name.trim().isEmpty) {
      throw const FormatException('配置名称不能为空');
    }
    if (interfaceName.trim().isEmpty) {
      throw const FormatException('请选择网络接口');
    }
    if (interfaceMetric != null &&
        (interfaceMetric! < 1 || interfaceMetric! > 9999)) {
      throw const FormatException('接口 Metric 应为 1～9999');
    }
    for (final route in staticRoutes) {
      route.validate();
    }
    if (mode == NetworkAddressMode.dhcp) return;
    _requireIpv4(address, 'IPv4 地址');
    if (prefixLength < 1 || prefixLength > 32) {
      throw const FormatException('IPv4 前缀长度应为 1～32');
    }
    if (gateway?.trim().isNotEmpty == true) {
      _requireIpv4(gateway, '默认网关');
    }
    for (final server in dnsServers) {
      _requireIpv4(server, 'DNS 服务器');
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'interfaceName': interfaceName,
    'interfaceMatchMode': interfaceMatchMode.name,
    'interfaceMacAddress': interfaceMacAddress,
    'interfaceTransport': interfaceTransport,
    'mode': mode.name,
    'address': address,
    'prefixLength': prefixLength,
    'gateway': gateway,
    'dnsServers': dnsServers,
    'interfaceMetric': interfaceMetric,
    'staticRoutes': [for (final value in staticRoutes) value.toJson()],
    'diagnostics': diagnostics.map((value) => value.name).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NetworkConfigurationTemplate.fromJson(
    Map<String, Object?> json,
  ) => NetworkConfigurationTemplate(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    interfaceName: json['interfaceName']?.toString() ?? '',
    interfaceMatchMode: NetworkInterfaceMatchMode.values.firstWhere(
      (value) => value.name == json['interfaceMatchMode'],
      orElse: () => NetworkInterfaceMatchMode.exactName,
    ),
    interfaceMacAddress: json['interfaceMacAddress']?.toString(),
    interfaceTransport: json['interfaceTransport']?.toString(),
    mode: NetworkAddressMode.values.firstWhere(
      (value) => value.name == json['mode'],
      orElse: () => NetworkAddressMode.dhcp,
    ),
    address: json['address']?.toString(),
    prefixLength: (json['prefixLength'] as num?)?.toInt() ?? 24,
    gateway: json['gateway']?.toString(),
    dnsServers: (json['dnsServers'] as List<Object?>? ?? const [])
        .map((value) => '$value')
        .where((value) => value.isNotEmpty)
        .toList(growable: false),
    interfaceMetric: (json['interfaceMetric'] as num?)?.toInt(),
    staticRoutes: (json['staticRoutes'] as List<Object?>? ?? const [])
        .whereType<Map>()
        .map(
          (value) => NetworkStaticRoute.fromJson(
            value.map<String, Object?>((key, value) => MapEntry('$key', value)),
          ),
        )
        .toList(growable: false),
    diagnostics:
        (json['diagnostics'] as List<Object?>?)
            ?.map(
              (raw) => NetworkDiagnosticKind.values.where(
                (value) => value.name == '$raw',
              ),
            )
            .expand((values) => values)
            .toSet() ??
        NetworkDiagnosticKind.values.toSet(),
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class NetworkInterfaceConfiguration {
  const NetworkInterfaceConfiguration({
    required this.interfaceName,
    required this.description,
    required this.status,
    required this.transport,
    required this.isDefault,
    required this.mode,
    this.interfaceIndex = 0,
    this.macAddress,
    this.linkSpeed,
    this.address,
    this.prefixLength,
    this.gateway,
    this.dnsServers = const [],
    this.interfaceMetric,
    this.profileName,
    this.profileCategory,
    this.routes = const [],
  });

  final String interfaceName;
  final int interfaceIndex;
  final String description;
  final String status;
  final String transport;
  final bool isDefault;
  final String? macAddress;
  final String? linkSpeed;
  final NetworkAddressMode mode;
  final String? address;
  final int? prefixLength;
  final String? gateway;
  final List<String> dnsServers;
  final int? interfaceMetric;
  final String? profileName;
  final String? profileCategory;
  final List<NetworkStaticRoute> routes;

  bool get connected =>
      const {'up', 'connected', 'activated'}.contains(status.toLowerCase());

  Map<String, Object?> toJson() => {
    'interfaceName': interfaceName,
    'interfaceIndex': interfaceIndex,
    'description': description,
    'status': status,
    'transport': transport,
    'isDefault': isDefault,
    'macAddress': macAddress,
    'linkSpeed': linkSpeed,
    'mode': mode.name,
    'address': address,
    'prefixLength': prefixLength,
    'gateway': gateway,
    'dnsServers': dnsServers,
    'interfaceMetric': interfaceMetric,
    'profileName': profileName,
    'profileCategory': profileCategory,
    'routes': [for (final value in routes) value.toJson()],
  };

  factory NetworkInterfaceConfiguration.fromJson(Map<String, Object?> json) =>
      NetworkInterfaceConfiguration(
        interfaceName: json['interfaceName']?.toString() ?? '',
        interfaceIndex: (json['interfaceIndex'] as num?)?.toInt() ?? 0,
        description: json['description']?.toString() ?? '',
        status: json['status']?.toString() ?? 'unknown',
        transport: json['transport']?.toString() ?? 'ethernet',
        isDefault: json['isDefault'] == true,
        macAddress: json['macAddress']?.toString(),
        linkSpeed: json['linkSpeed']?.toString(),
        mode: NetworkAddressMode.values.firstWhere(
          (value) => value.name == json['mode'],
          orElse: () => NetworkAddressMode.dhcp,
        ),
        address: json['address']?.toString(),
        prefixLength: (json['prefixLength'] as num?)?.toInt(),
        gateway: json['gateway']?.toString(),
        dnsServers: _strings(json['dnsServers']),
        interfaceMetric: (json['interfaceMetric'] as num?)?.toInt(),
        profileName: json['profileName']?.toString(),
        profileCategory: json['profileCategory']?.toString(),
        routes: (json['routes'] as List<Object?>? ?? const [])
            .whereType<Map>()
            .map(
              (value) => NetworkStaticRoute.fromJson(
                value.map<String, Object?>(
                  (key, value) => MapEntry('$key', value),
                ),
              ),
            )
            .toList(growable: false),
      );
}

class NetworkConfigurationDifference {
  const NetworkConfigurationDifference({
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final String before;
  final String after;
  bool get changed => before != after;
}

class NetworkConfigurationVerificationItem {
  const NetworkConfigurationVerificationItem({
    required this.label,
    required this.expected,
    required this.actual,
    required this.matches,
    this.detail,
    this.requiredForWrite = true,
  });

  final String label;
  final String expected;
  final String actual;
  final bool matches;
  final String? detail;
  final bool requiredForWrite;
}

class NetworkConnectivityCheck {
  const NetworkConnectivityCheck({
    required this.kind,
    required this.state,
    required this.title,
    required this.detail,
    this.latencyMs,
  });

  final NetworkDiagnosticKind kind;
  final NetworkCheckState state;
  final String title;
  final String detail;
  final double? latencyMs;
}

class NetworkConnectivityReport {
  const NetworkConnectivityReport({
    required this.interfaceName,
    required this.checkedAt,
    required this.checks,
  });

  final String interfaceName;
  final DateTime checkedAt;
  final List<NetworkConnectivityCheck> checks;

  bool get hasWarnings =>
      checks.any((value) => value.state == NetworkCheckState.warning);
}

class IpConflictCheckResult {
  const IpConflictCheckResult({
    required this.state,
    required this.address,
    required this.message,
    this.macAddress,
  });

  final IpConflictState state;
  final String address;
  final String message;
  final String? macAddress;
}

class NetworkConfigurationRestorePoint {
  const NetworkConfigurationRestorePoint({
    required this.id,
    required this.platform,
    required this.interfaceName,
    required this.capturedAt,
    required this.configuration,
    required this.raw,
  });

  final String id;
  final String platform;
  final String interfaceName;
  final DateTime capturedAt;
  final NetworkInterfaceConfiguration configuration;
  final Map<String, Object?> raw;

  Map<String, Object?> toJson() => {
    'id': id,
    'platform': platform,
    'interfaceName': interfaceName,
    'capturedAt': capturedAt.toIso8601String(),
    'configuration': configuration.toJson(),
    'raw': raw,
  };

  factory NetworkConfigurationRestorePoint.fromJson(
    Map<String, Object?> json,
  ) => NetworkConfigurationRestorePoint(
    id: json['id']?.toString() ?? '',
    platform: json['platform']?.toString() ?? '',
    interfaceName: json['interfaceName']?.toString() ?? '',
    capturedAt:
        DateTime.tryParse(json['capturedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    configuration: NetworkInterfaceConfiguration.fromJson(
      (json['configuration'] as Map? ?? const {}).map<String, Object?>(
        (key, value) => MapEntry('$key', value),
      ),
    ),
    raw: (json['raw'] as Map? ?? const {}).map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    ),
  );
}

class NetworkConfigurationApplyResult {
  const NetworkConfigurationApplyResult({
    required this.success,
    required this.message,
    this.requiresElevation = false,
    this.rollbackAttempted = false,
    this.rollbackSucceeded = false,
    this.observedAddress,
    this.verification = const [],
  });

  final bool success;
  final String message;
  final bool requiresElevation;
  final bool rollbackAttempted;
  final bool rollbackSucceeded;
  final String? observedAddress;
  final List<NetworkConfigurationVerificationItem> verification;

  NetworkConfigurationApplyResult copyWith({
    bool? success,
    String? message,
    List<NetworkConfigurationVerificationItem>? verification,
  }) => NetworkConfigurationApplyResult(
    success: success ?? this.success,
    message: message ?? this.message,
    requiresElevation: requiresElevation,
    rollbackAttempted: rollbackAttempted,
    rollbackSucceeded: rollbackSucceeded,
    observedAddress: observedAddress,
    verification: verification ?? this.verification,
  );

  factory NetworkConfigurationApplyResult.fromJson(Map<String, Object?> json) =>
      NetworkConfigurationApplyResult(
        success: json['success'] == true,
        message: json['message']?.toString() ?? '网络配置没有返回结果',
        requiresElevation: json['requiresElevation'] == true,
        rollbackAttempted: json['rollbackAttempted'] == true,
        rollbackSucceeded: json['rollbackSucceeded'] == true,
        observedAddress: json['observedAddress']?.toString(),
      );
}

String encodeNetworkTemplates(List<NetworkConfigurationTemplate> values) =>
    jsonEncode([for (final value in values) value.toJson()]);

List<NetworkConfigurationTemplate> decodeNetworkTemplates(String? source) {
  if (source == null || source.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(source);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map(
          (row) => NetworkConfigurationTemplate.fromJson(
            row.map<String, Object?>((key, value) => MapEntry('$key', value)),
          ),
        )
        .where((value) => value.id.isNotEmpty)
        .toList(growable: false);
  } on FormatException {
    return const [];
  }
}

String encodeNetworkRestorePoint(NetworkConfigurationRestorePoint value) =>
    jsonEncode(value.toJson());

NetworkConfigurationRestorePoint? decodeNetworkRestorePoint(String? source) {
  if (source == null || source.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map) return null;
    return NetworkConfigurationRestorePoint.fromJson(
      decoded.map<String, Object?>((key, value) => MapEntry('$key', value)),
    );
  } on FormatException {
    return null;
  }
}

void _requireIpv4(String? value, String label) {
  final parsed = value == null ? null : InternetAddress.tryParse(value.trim());
  if (parsed == null || parsed.type != InternetAddressType.IPv4) {
    throw FormatException('$label不是有效的 IPv4 地址');
  }
}

List<String> _strings(Object? value) => (value is List ? value : const [])
    .map((item) => '$item')
    .where((item) => item.isNotEmpty)
    .toList(growable: false);
