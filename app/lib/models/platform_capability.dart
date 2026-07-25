enum CapabilityId {
  wifiScan,
  bluetoothClassic,
  bluetoothLowEnergy,
  smb,
  interfaceTraffic,
  processTraffic,
  enhancedProcessTraffic,
  packetCapture,
}

enum CapabilityState {
  available,
  partial,
  permissionRequired,
  dependencyMissing,
  elevationRequired,
  unsupported,
}

class CapabilityRecoveryAction {
  const CapabilityRecoveryAction({
    required this.id,
    required this.labelKey,
    this.command,
  });

  final String id;
  final String labelKey;
  final String? command;
}

class PlatformCapability {
  const PlatformCapability({
    required this.id,
    required this.state,
    required this.reasonCode,
    this.technicalDetail,
    this.actions = const [],
  });

  final CapabilityId id;
  final CapabilityState state;
  final String reasonCode;
  final String? technicalDetail;
  final List<CapabilityRecoveryAction> actions;

  bool get canOpen => state != CapabilityState.unsupported;
  bool get canRun => state == CapabilityState.available || state == CapabilityState.partial;
}

class PlatformCapabilities {
  const PlatformCapabilities({
    required this.detectedAt,
    required this.values,
  });

  final DateTime detectedAt;
  final Map<CapabilityId, PlatformCapability> values;

  PlatformCapability operator [](CapabilityId id) => values[id] ??
      PlatformCapability(
        id: id,
        state: CapabilityState.unsupported,
        reasonCode: 'capability.notProbed',
      );
}
