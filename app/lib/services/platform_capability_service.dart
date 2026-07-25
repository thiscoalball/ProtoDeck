import 'dart:io';

import '../models/platform_capability.dart';

class PlatformCapabilityService {
  PlatformCapabilities? _cached;

  Future<PlatformCapabilities> probe({bool force = false}) async {
    final cached = _cached;
    if (!force && cached != null) return cached;

    final values = Platform.isAndroid
        ? _android()
        : Platform.isWindows
        ? await _windows()
        : Platform.isLinux
        ? await _linux()
        : _unsupported();
    return _cached = PlatformCapabilities(
      detectedAt: DateTime.now(),
      values: values,
    );
  }

  Map<CapabilityId, PlatformCapability> _android() => {
    for (final id in CapabilityId.values)
      id: PlatformCapability(
        id: id,
        state: switch (id) {
          CapabilityId.enhancedProcessTraffic => CapabilityState.unsupported,
          CapabilityId.packetCapture => CapabilityState.partial,
          _ => CapabilityState.available,
        },
        reasonCode: switch (id) {
          CapabilityId.enhancedProcessTraffic =>
            'capability.androidNoEnhancedTraffic',
          CapabilityId.packetCapture => 'capability.offlineCaptureOnly',
          _ => 'capability.ready',
        },
      ),
  };

  Future<Map<CapabilityId, PlatformCapability>> _windows() async {
    final enhancedHelper = await File(
      '${File(Platform.resolvedExecutable).parent.path}/protodeck_etw_helper.exe',
    ).exists();
    return {
      CapabilityId.wifiScan: _ready(CapabilityId.wifiScan),
      CapabilityId.bluetoothClassic: _ready(CapabilityId.bluetoothClassic),
      CapabilityId.bluetoothLowEnergy: _ready(CapabilityId.bluetoothLowEnergy),
      CapabilityId.smb: _ready(CapabilityId.smb),
      CapabilityId.interfaceTraffic: _ready(CapabilityId.interfaceTraffic),
      CapabilityId.processTraffic: _partial(
        CapabilityId.processTraffic,
        'capability.connectionOwnershipOnly',
      ),
      CapabilityId.enhancedProcessTraffic: enhancedHelper
          ? _elevation(
              CapabilityId.enhancedProcessTraffic,
              'capability.etwElevationRequired',
            )
          : _missing(
              CapabilityId.enhancedProcessTraffic,
              'capability.enhancedHelperMissing',
            ),
      CapabilityId.packetCapture: _partial(
        CapabilityId.packetCapture,
        'capability.offlineCaptureOnly',
      ),
    };
  }

  Future<Map<CapabilityId, PlatformCapability>> _linux() async {
    final bluetoothctl = await _commandAvailable('bluetoothctl');
    final bluezActive = bluetoothctl && await _isServiceActive('bluetooth');
    final smbLibrary = await _hasLinuxLibrary('libsmbclient.so');
    final smbHelper = await File(
      '${File(Platform.resolvedExecutable).parent.path}/protodeck_smb_helper',
    ).exists();
    final bpftool = await _commandAvailable('bpftool');
    final enhancedHelper = await File(
      '${File(Platform.resolvedExecutable).parent.path}/protodeck_traffic_helper',
    ).exists();
    return {
      CapabilityId.wifiScan: _ready(CapabilityId.wifiScan),
      CapabilityId.bluetoothClassic: bluezActive
          ? _ready(CapabilityId.bluetoothClassic)
          : _linuxBluetoothMissing(CapabilityId.bluetoothClassic),
      CapabilityId.bluetoothLowEnergy: bluezActive
          ? _ready(CapabilityId.bluetoothLowEnergy)
          : _linuxBluetoothMissing(CapabilityId.bluetoothLowEnergy),
      CapabilityId.smb: smbLibrary && smbHelper
          ? _ready(CapabilityId.smb)
          : PlatformCapability(
              id: CapabilityId.smb,
              state: CapabilityState.dependencyMissing,
              reasonCode: 'capability.libsmbclientMissing',
              actions: const [
                CapabilityRecoveryAction(
                  id: 'copyCommand',
                  labelKey: 'capability.copyInstallCommand',
                  command: 'sudo apt install libsmbclient',
                ),
              ],
            ),
      CapabilityId.interfaceTraffic: _ready(CapabilityId.interfaceTraffic),
      CapabilityId.processTraffic: _partial(
        CapabilityId.processTraffic,
        'capability.connectionOwnershipOnly',
      ),
      CapabilityId.enhancedProcessTraffic: bpftool && enhancedHelper
          ? _elevation(
              CapabilityId.enhancedProcessTraffic,
              'capability.ebpfElevationRequired',
            )
          : _missing(
              CapabilityId.enhancedProcessTraffic,
              enhancedHelper
                  ? 'capability.ebpfRuntimeMissing'
                  : 'capability.enhancedHelperMissing',
              command: enhancedHelper ? 'sudo apt install bpftool' : null,
            ),
      CapabilityId.packetCapture: _partial(
        CapabilityId.packetCapture,
        'capability.offlineCaptureOnly',
      ),
    };
  }

  Map<CapabilityId, PlatformCapability> _unsupported() => {
    for (final id in CapabilityId.values)
      id: PlatformCapability(
        id: id,
        state: CapabilityState.unsupported,
        reasonCode: 'capability.platformUnsupported',
      ),
  };

  PlatformCapability _ready(CapabilityId id) => PlatformCapability(
    id: id,
    state: CapabilityState.available,
    reasonCode: 'capability.ready',
  );

  PlatformCapability _partial(CapabilityId id, String reason) =>
      PlatformCapability(
        id: id,
        state: CapabilityState.partial,
        reasonCode: reason,
      );

  PlatformCapability _missing(
    CapabilityId id,
    String reason, {
    String? command,
  }) => PlatformCapability(
    id: id,
    state: CapabilityState.dependencyMissing,
    reasonCode: reason,
    actions: command == null
        ? const []
        : [
            CapabilityRecoveryAction(
              id: 'copyCommand',
              labelKey: 'capability.copyInstallCommand',
              command: command,
            ),
          ],
  );

  PlatformCapability _elevation(CapabilityId id, String reason) =>
      PlatformCapability(
        id: id,
        state: CapabilityState.elevationRequired,
        reasonCode: reason,
        actions: const [
          CapabilityRecoveryAction(
            id: 'elevate',
            labelKey: 'capability.enableEnhancedMonitoring',
          ),
        ],
      );

  PlatformCapability _linuxBluetoothMissing(CapabilityId id) =>
      PlatformCapability(
        id: id,
        state: CapabilityState.dependencyMissing,
        reasonCode: 'capability.bluezUnavailable',
        actions: const [
          CapabilityRecoveryAction(
            id: 'copyCommand',
            labelKey: 'capability.copyInstallCommand',
            command: 'sudo apt install bluez libbluetooth3',
          ),
        ],
      );

  Future<bool> _commandAvailable(String command) async {
    try {
      final executable = Platform.isWindows ? 'where.exe' : 'which';
      return (await Process.run(executable, [command])).exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<bool> _isServiceActive(String service) async {
    try {
      return (await Process.run('systemctl', [
            'is-active',
            '--quiet',
            service,
          ])).exitCode ==
          0;
    } on Object {
      return false;
    }
  }

  Future<bool> _hasLinuxLibrary(String name) async {
    try {
      final result = await Process.run('ldconfig', ['-p']);
      return result.exitCode == 0 && result.stdout.toString().contains(name);
    } on Object {
      return false;
    }
  }
}
