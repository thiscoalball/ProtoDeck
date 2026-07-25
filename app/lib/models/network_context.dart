class NetworkAddressInfo {
  const NetworkAddressInfo({
    required this.address,
    required this.prefixLength,
    required this.family,
  });

  final String address;
  final int prefixLength;
  final String family;

  factory NetworkAddressInfo.fromMap(Map<Object?, Object?> map) =>
      NetworkAddressInfo(
        address: map['address'] as String? ?? '',
        prefixLength: map['prefixLength'] as int? ?? 0,
        family: map['family'] as String? ?? '',
      );
}

class WifiConnectionInfo {
  const WifiConnectionInfo({
    this.ssid,
    this.bssid,
    this.rssi,
    this.signalLevel,
    this.frequency,
    this.channel,
    this.linkSpeedMbps,
    this.rxLinkSpeedMbps,
    this.txLinkSpeedMbps,
    this.standard,
  });

  final String? ssid;
  final String? bssid;
  final int? rssi;
  final int? signalLevel;
  final int? frequency;
  final int? channel;
  final int? linkSpeedMbps;
  final int? rxLinkSpeedMbps;
  final int? txLinkSpeedMbps;
  final String? standard;

  factory WifiConnectionInfo.fromMap(Map<Object?, Object?> map) =>
      WifiConnectionInfo(
        ssid: map['ssid'] as String?,
        bssid: map['bssid'] as String?,
        rssi: map['rssi'] as int?,
        signalLevel: map['signalLevel'] as int?,
        frequency: map['frequency'] as int?,
        channel: map['channel'] as int?,
        linkSpeedMbps: map['linkSpeedMbps'] as int?,
        rxLinkSpeedMbps: map['rxLinkSpeedMbps'] as int?,
        txLinkSpeedMbps: map['txLinkSpeedMbps'] as int?,
        standard: map['standard'] as String?,
      );
}

class CellularConnectionInfo {
  const CellularConnectionInfo({
    this.operatorName,
    this.operatorCode,
    this.simOperatorName,
    this.simOperatorCode,
    this.radioTechnology,
    this.dbm,
    this.level,
    this.roaming = false,
    this.registered = false,
    this.neighborCellCount = 0,
    this.metrics = const {},
    this.identity = const {},
  });

  final String? operatorName;
  final String? operatorCode;
  final String? simOperatorName;
  final String? simOperatorCode;
  final String? radioTechnology;
  final int? dbm;
  final int? level;
  final bool roaming;
  final bool registered;
  final int neighborCellCount;
  final Map<String, int> metrics;
  final Map<String, String> identity;

  factory CellularConnectionInfo.fromMap(Map<Object?, Object?> map) =>
      CellularConnectionInfo(
        operatorName: map['operatorName'] as String?,
        operatorCode: map['operatorCode'] as String?,
        simOperatorName: map['simOperatorName'] as String?,
        simOperatorCode: map['simOperatorCode'] as String?,
        radioTechnology: map['radioTechnology'] as String?,
        dbm: map['dbm'] as int?,
        level: map['level'] as int?,
        roaming: map['roaming'] as bool? ?? false,
        registered: map['registered'] as bool? ?? false,
        neighborCellCount: map['neighborCellCount'] as int? ?? 0,
        metrics: (map['metrics'] as Map<Object?, Object?>? ?? const {}).map(
          (key, value) => MapEntry('$key', value as int),
        ),
        identity: (map['identity'] as Map<Object?, Object?>? ?? const {}).map(
          (key, value) => MapEntry('$key', '$value'),
        ),
      );
}

class NetworkAdapterInfo {
  const NetworkAdapterInfo({
    required this.interfaceIndex,
    required this.name,
    required this.description,
    required this.status,
    required this.transport,
    required this.isDefault,
    this.macAddress,
    this.linkSpeed,
    this.mtu = 0,
    this.addresses = const [],
    this.dnsServers = const [],
    this.gateways = const [],
  });

  final int interfaceIndex;
  final String name;
  final String description;
  final String status;
  final String transport;
  final bool isDefault;
  final String? macAddress;
  final String? linkSpeed;
  final int mtu;
  final List<NetworkAddressInfo> addresses;
  final List<String> dnsServers;
  final List<String> gateways;

  factory NetworkAdapterInfo.fromMap(Map<Object?, Object?> map) =>
      NetworkAdapterInfo(
        interfaceIndex: map['interfaceIndex'] as int? ?? 0,
        name: map['name'] as String? ?? '',
        description: map['description'] as String? ?? '',
        status: map['status'] as String? ?? 'Unknown',
        transport: map['transport'] as String? ?? 'ethernet',
        isDefault: map['isDefault'] as bool? ?? false,
        macAddress: map['macAddress'] as String?,
        linkSpeed: map['linkSpeed'] as String?,
        mtu: map['mtu'] as int? ?? 0,
        addresses: (map['addresses'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map(NetworkAddressInfo.fromMap)
            .toList(growable: false),
        dnsServers: (map['dnsServers'] as List<Object?>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        gateways: (map['gateways'] as List<Object?>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
      );
}

class NetworkContext {
  const NetworkContext({
    required this.connected,
    required this.interfaceName,
    required this.transports,
    required this.validated,
    this.captivePortal = false,
    this.partialConnectivity = false,
    required this.metered,
    required this.addresses,
    required this.dnsServers,
    required this.gateways,
    this.lanAddresses = const [],
    this.lanGateways = const [],
    required this.mtu,
    this.wifi,
    this.cellular,
    this.publicIpv4,
    this.publicIpv6,
    this.adapters = const [],
  });

  final bool connected;
  final String? interfaceName;
  final List<String> transports;
  final bool validated;
  final bool captivePortal;
  final bool partialConnectivity;
  final bool metered;
  final List<NetworkAddressInfo> addresses;
  final List<String> dnsServers;
  final List<String> gateways;
  final List<NetworkAddressInfo> lanAddresses;
  final List<String> lanGateways;
  final int mtu;
  final WifiConnectionInfo? wifi;
  final CellularConnectionInfo? cellular;
  final String? publicIpv4;
  final String? publicIpv6;
  final List<NetworkAdapterInfo> adapters;

  NetworkAdapterInfo? get defaultAdapter =>
      adapters.where((adapter) => adapter.isDefault).firstOrNull;

  bool get usesVpn => transports.contains('vpn');

  NetworkContext copyWith({String? publicIpv4, String? publicIpv6}) =>
      NetworkContext(
        connected: connected,
        interfaceName: interfaceName,
        transports: transports,
        validated: validated,
        captivePortal: captivePortal,
        partialConnectivity: partialConnectivity,
        metered: metered,
        addresses: addresses,
        dnsServers: dnsServers,
        gateways: gateways,
        lanAddresses: lanAddresses,
        lanGateways: lanGateways,
        mtu: mtu,
        wifi: wifi,
        cellular: cellular,
        publicIpv4: publicIpv4 ?? this.publicIpv4,
        publicIpv6: publicIpv6 ?? this.publicIpv6,
        adapters: adapters,
      );

  factory NetworkContext.fromMap(Map<Object?, Object?> map) {
    final wifiMap = map['wifi'];
    final cellularMap = map['cellular'];
    return NetworkContext(
      connected: map['connected'] as bool? ?? false,
      interfaceName: map['interfaceName'] as String?,
      transports: (map['transports'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      validated: map['validated'] as bool? ?? false,
      captivePortal: map['captivePortal'] as bool? ?? false,
      partialConnectivity: map['partialConnectivity'] as bool? ?? false,
      metered: map['metered'] as bool? ?? false,
      addresses: (map['addresses'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(NetworkAddressInfo.fromMap)
          .toList(growable: false),
      dnsServers: (map['dnsServers'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      gateways: (map['gateways'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      lanAddresses: (map['lanAddresses'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(NetworkAddressInfo.fromMap)
          .toList(growable: false),
      lanGateways: (map['lanGateways'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      mtu: map['mtu'] as int? ?? 0,
      wifi: wifiMap is Map<Object?, Object?>
          ? WifiConnectionInfo.fromMap(wifiMap)
          : null,
      cellular: cellularMap is Map<Object?, Object?>
          ? CellularConnectionInfo.fromMap(cellularMap)
          : null,
      adapters: (map['adapters'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(NetworkAdapterInfo.fromMap)
          .toList(growable: false),
    );
  }
}

class WifiAccessPoint {
  const WifiAccessPoint({
    required this.ssid,
    required this.bssid,
    required this.rssi,
    required this.signalLevel,
    required this.frequency,
    required this.channel,
    required this.channelWidth,
    required this.security,
    required this.timestampMicros,
  });

  final String ssid;
  final String bssid;
  final int rssi;
  final int signalLevel;
  final int frequency;
  final int channel;
  final String channelWidth;
  final String security;
  final int timestampMicros;

  factory WifiAccessPoint.fromMap(Map<Object?, Object?> map) => WifiAccessPoint(
    ssid: map['ssid'] as String? ?? '',
    bssid: map['bssid'] as String? ?? '',
    rssi: map['rssi'] as int? ?? -127,
    signalLevel: map['signalLevel'] as int? ?? 0,
    frequency: map['frequency'] as int? ?? 0,
    channel: map['channel'] as int? ?? 0,
    channelWidth: map['channelWidth'] as String? ?? '未知',
    security: map['security'] as String? ?? '',
    timestampMicros: map['timestampMicros'] as int? ?? 0,
  );
}

class WifiScanSnapshot {
  const WifiScanSnapshot({
    required this.accessPoints,
    required this.fresh,
    required this.requested,
    required this.status,
    required this.collectedAt,
    this.newestResultAge,
  });

  final List<WifiAccessPoint> accessPoints;
  final bool fresh;
  final bool requested;
  final String status;
  final DateTime collectedAt;
  final Duration? newestResultAge;

  factory WifiScanSnapshot.fromMap(Map<Object?, Object?> map) {
    final ageMillis = map['newestResultAgeMillis'] as int?;
    return WifiScanSnapshot(
      accessPoints: (map['accessPoints'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(WifiAccessPoint.fromMap)
          .toList(growable: false),
      fresh: map['fresh'] as bool? ?? false,
      requested: map['requested'] as bool? ?? false,
      status: map['status'] as String? ?? 'unknown',
      collectedAt: DateTime.fromMillisecondsSinceEpoch(
        map['collectedAtMillis'] as int? ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      newestResultAge: ageMillis == null
          ? null
          : Duration(milliseconds: ageMillis),
    );
  }
}
