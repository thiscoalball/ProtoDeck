import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';

/// Real BlueZ backend used by the Linux desktop build.
///
/// It intentionally talks to the system bus instead of scraping bluetoothctl,
/// so credentials and binary GATT values never pass through a shell.
class LinuxBluezService {
  static const _bluez = 'org.bluez';
  static const _adapterInterface = 'org.bluez.Adapter1';
  static const _deviceInterface = 'org.bluez.Device1';
  static const _serviceInterface = 'org.bluez.GattService1';
  static const _characteristicInterface = 'org.bluez.GattCharacteristic1';
  static const _profileManagerInterface = 'org.bluez.ProfileManager1';
  static const _gattManagerInterface = 'org.bluez.GattManager1';
  static const _advertisingManagerInterface = 'org.bluez.LEAdvertisingManager1';

  final DBusClient _client = DBusClient.system();
  late final DBusRemoteObjectManager _manager = DBusRemoteObjectManager(
    _client,
    name: _bluez,
    path: DBusObjectPath('/'),
  );
  final Queue<Map<Object?, Object?>> _events = Queue();
  final Map<String, String> _fingerprints = {};
  StreamSubscription<DBusSignal>? _subscription;
  DBusObjectPath? _adapterPath;
  DBusObjectPath? _connectedDevice;
  bool _scanning = false;
  bool _classicDiscovery = false;
  _BluezRfcommProfile? _rfcommProfile;
  RandomAccessFile? _rfcommFile;
  DBusObjectPath? _rfcommDevice;
  String? _rfcommUuid;
  DBusObject? _gattRoot;
  _BluezGattService? _localGattService;
  _BluezGattCharacteristic? _localGattCharacteristic;
  _BluezAdvertisement? _advertisement;

  Future<Map<Object?, Object?>> status() async {
    try {
      final objects = await _manager.getManagedObjects();
      final adapter = _findInterface(objects, _adapterInterface);
      if (adapter == null) {
        return _failure(
          'bluetooth.adapterMissing',
          'BlueZ did not expose a Bluetooth adapter',
        );
      }
      _adapterPath = adapter.$1;
      final values = adapter.$2;
      return {
        'supported': true,
        'enabled': _native<bool>(values['Powered']) ?? false,
        'name': _native<String>(values['Alias']),
        'address': _native<String>(values['Address']),
        'ble': true,
        'advertising': objects.values.any(
          (value) => value.containsKey('org.bluez.LEAdvertisingManager1'),
        ),
        'extendedAdvertising': false,
        'platform': 'linux',
        'permissions': const {'scan': true, 'connect': true, 'advertise': true},
      };
    } on Object catch (error) {
      return _failure('bluetooth.bluezUnavailable', error.toString());
    }
  }

  Future<List<Map<Object?, Object?>>> bondedDevices() async {
    final objects = await _manager.getManagedObjects();
    return _devices(
      objects,
    ).where((device) => device['bonded'] == true).toList(growable: false);
  }

  Future<void> startDiscovery({required bool classic}) async {
    final adapter = await _adapter();
    await _ensureSubscription();
    try {
      await adapter.callMethod(_adapterInterface, 'SetDiscoveryFilter', [
        DBusDict.stringVariant({
          'Transport': DBusString(classic ? 'auto' : 'le'),
          'DuplicateData': const DBusBoolean(true),
        }),
      ]);
    } on DBusMethodResponseException {
      // Older BlueZ releases may not support all filter properties. Discovery
      // itself is still valid, so retry without a filter.
    }
    await adapter.callMethod(_adapterInterface, 'StartDiscovery', const []);
    _scanning = true;
    _classicDiscovery = classic;
    _events.add(
      _event(classic ? 'classicScan' : 'bleScan', {'state': 'started'}),
    );
    await _refreshDevices(classic: classic);
  }

  Future<void> stopDiscovery({required bool classic}) async {
    final adapter = await _adapter();
    try {
      await adapter.callMethod(_adapterInterface, 'StopDiscovery', const []);
    } on DBusMethodResponseException {
      // BlueZ returns NotReady when discovery already ended.
    }
    _scanning = false;
    _events.add(
      _event(classic ? 'classicScan' : 'bleScan', {'state': 'stopped'}),
    );
  }

  Future<Map<Object?, Object?>?> pollEvent() async {
    if (_scanning) await _refreshDevices(classic: _classicDiscovery);
    return _events.isEmpty ? null : _events.removeFirst();
  }

  Future<void> connectClassic(String address, String uuid) async {
    await _stopClassic(emitEvent: false);
    await _ensureSubscription();
    final found = await _deviceByAddress(address);
    _events.add(
      _event('classicConnection', {
        'state': 'connecting',
        'peer': address,
        'uuid': uuid,
      }),
    );
    await _registerRfcommProfile(uuid: uuid, role: 'client', name: 'ProtoDeck');
    _rfcommDevice = found.$1;
    _rfcommUuid = uuid;
    try {
      await found.$2.callMethod(_deviceInterface, 'ConnectProfile', [
        DBusString(uuid),
      ]);
    } on Object {
      await _stopClassic(emitEvent: false);
      rethrow;
    }
  }

  Future<void> startClassicServer(String name, String uuid) async {
    await _stopClassic(emitEvent: false);
    await _ensureSubscription();
    _rfcommUuid = uuid;
    await _registerRfcommProfile(
      uuid: uuid,
      role: 'server',
      name: name.trim().isEmpty ? 'ProtoDeck RFCOMM' : name.trim(),
    );
    _events.add(
      _event('classicServer', {
        'state': 'listening',
        'name': name,
        'uuid': uuid,
      }),
    );
  }

  Future<void> sendClassic(Uint8List bytes) async {
    final file = _rfcommFile;
    if (file == null) throw StateError('bluetooth.rfcommNotConnected');
    await file.writeFrom(bytes);
    await file.flush();
    _events.add(
      _event('data', {
        'transport': 'Classic',
        'direction': 'TX',
        'operation': 'write',
        'bytes': bytes,
      }),
    );
  }

  Future<void> stopClassic() => _stopClassic(emitEvent: true);

  Future<void> _registerRfcommProfile({
    required String uuid,
    required String role,
    required String name,
  }) async {
    final path = DBusObjectPath('/io/protodeck/bluetooth/rfcomm');
    final profile = _BluezRfcommProfile(
      path,
      onConnection: _acceptRfcommConnection,
      onDisconnection: _handleRfcommDisconnection,
      onRelease: () => unawaited(_stopClassic(emitEvent: true)),
    );
    await _client.registerObject(profile);
    try {
      final manager = DBusRemoteObject(
        _client,
        name: _bluez,
        path: DBusObjectPath('/org/bluez'),
      );
      await manager.callMethod(_profileManagerInterface, 'RegisterProfile', [
        path,
        DBusString(uuid),
        DBusDict.stringVariant({
          'Name': DBusString(name),
          'Role': DBusString(role),
          'Service': DBusString(uuid),
          'RequireAuthentication': const DBusBoolean(false),
          'RequireAuthorization': const DBusBoolean(false),
          'AutoConnect': DBusBoolean(role == 'client'),
        }),
      ]);
      _rfcommProfile = profile;
    } on Object {
      await _client.unregisterObject(profile);
      rethrow;
    }
  }

  Future<void> _acceptRfcommConnection(
    DBusObjectPath device,
    ResourceHandle handle,
  ) async {
    await _closeRfcommFile();
    _rfcommDevice = device;
    final file = handle.toFile();
    _rfcommFile = file;
    final objects = await _manager.getManagedObjects();
    final address = _native<String>(
      objects[device]?[_deviceInterface]?['Address'],
    );
    _events.add(
      _event('classicConnection', {
        'state': 'connected',
        'peer': address ?? device.value,
        'uuid': _rfcommUuid,
        'status': 0,
      }),
    );
    unawaited(_readRfcomm(file));
  }

  Future<void> _readRfcomm(RandomAccessFile file) async {
    try {
      while (identical(file, _rfcommFile)) {
        final bytes = await file.read(4096);
        if (bytes.isEmpty) break;
        _events.add(
          _event('data', {
            'transport': 'Classic',
            'direction': 'RX',
            'operation': 'stream',
            'bytes': Uint8List.fromList(bytes),
          }),
        );
      }
    } on Object catch (error) {
      if (identical(file, _rfcommFile)) {
        _events.add(
          _event('classicConnection', {
            'state': 'error',
            'errorCode': 'bluetooth.rfcommReadFailed',
            'technicalDetails': error.toString(),
          }),
        );
      }
    } finally {
      if (identical(file, _rfcommFile)) {
        _rfcommFile = null;
        try {
          await file.close();
        } on Object {
          // The remote side may have already closed the descriptor.
        }
        _events.add(
          _event('classicConnection', {'state': 'disconnected', 'status': 0}),
        );
      }
    }
  }

  Future<void> _handleRfcommDisconnection(DBusObjectPath device) async {
    if (_rfcommDevice == device) await _closeRfcommFile();
  }

  Future<void> _closeRfcommFile() async {
    final file = _rfcommFile;
    _rfcommFile = null;
    if (file != null) {
      try {
        await file.close();
      } on Object {
        // Closing an already released BlueZ descriptor is harmless.
      }
    }
  }

  Future<void> _stopClassic({required bool emitEvent}) async {
    final device = _rfcommDevice;
    final uuid = _rfcommUuid;
    _rfcommDevice = null;
    _rfcommUuid = null;
    if (device != null && uuid != null) {
      try {
        await DBusRemoteObject(
          _client,
          name: _bluez,
          path: device,
        ).callMethod(_deviceInterface, 'DisconnectProfile', [DBusString(uuid)]);
      } on Object {
        // It is valid to stop a server that has no active peer.
      }
    }
    await _closeRfcommFile();
    final profile = _rfcommProfile;
    _rfcommProfile = null;
    if (profile != null) {
      try {
        await DBusRemoteObject(
          _client,
          name: _bluez,
          path: DBusObjectPath('/org/bluez'),
        ).callMethod(_profileManagerInterface, 'UnregisterProfile', [
          profile.path,
        ]);
      } on Object {
        // BlueZ may already have released the profile during shutdown.
      }
      await _client.unregisterObject(profile);
    }
    if (emitEvent) {
      _events.add(
        _event('classicConnection', {'state': 'disconnected', 'status': 0}),
      );
    }
  }

  Future<void> connectBle(String address) async {
    await _ensureSubscription();
    final found = await _deviceByAddress(address);
    await found.$2.callMethod(_deviceInterface, 'Connect', const []);
    _connectedDevice = found.$1;
    _events.add(
      _event('bleConnection', {
        'state': 'connected',
        'peer': address,
        'status': 0,
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _emitGattTree();
  }

  Future<void> disconnectBle() async {
    final path = _connectedDevice;
    if (path == null) return;
    final object = DBusRemoteObject(_client, name: _bluez, path: path);
    try {
      await object.callMethod(_deviceInterface, 'Disconnect', const []);
    } finally {
      _connectedDevice = null;
      _events.add(
        _event('bleConnection', {'state': 'disconnected', 'status': 0}),
      );
    }
  }

  Future<void> startGattServer(
    String serviceUuid,
    String characteristicUuid, {
    required bool advertise,
  }) async {
    await stopGattServer();
    final adapter = await _adapter();
    final root = DBusObject(
      DBusObjectPath('/io/protodeck/bluetooth/gatt'),
      isObjectManager: true,
    );
    final service = _BluezGattService(
      DBusObjectPath('/io/protodeck/bluetooth/gatt/service0'),
      uuid: serviceUuid,
    );
    final characteristic = _BluezGattCharacteristic(
      DBusObjectPath('/io/protodeck/bluetooth/gatt/service0/char0'),
      uuid: characteristicUuid,
      servicePath: service.path,
      onWrite: (bytes) {
        _events.add(
          _event('data', {
            'transport': 'BLE Server',
            'direction': 'RX',
            'operation': 'write',
            'characteristic': characteristicUuid,
            'bytes': bytes,
          }),
        );
      },
    );
    await _client.registerObject(root);
    await _client.registerObject(service);
    await _client.registerObject(characteristic);
    try {
      await adapter.callMethod(_gattManagerInterface, 'RegisterApplication', [
        root.path,
        DBusDict.stringVariant(const {}),
      ]);
      _gattRoot = root;
      _localGattService = service;
      _localGattCharacteristic = characteristic;
      if (advertise) {
        final advertisement = _BluezAdvertisement(
          DBusObjectPath('/io/protodeck/bluetooth/advertisement0'),
          serviceUuid: serviceUuid,
        );
        await _client.registerObject(advertisement);
        try {
          await adapter.callMethod(
            _advertisingManagerInterface,
            'RegisterAdvertisement',
            [advertisement.path, DBusDict.stringVariant(const {})],
          );
          _advertisement = advertisement;
        } on Object {
          await _client.unregisterObject(advertisement);
          rethrow;
        }
      }
      _events.add(
        _event('bleServer', {
          'state': 'started',
          'service': serviceUuid,
          'characteristic': characteristicUuid,
          'advertising': advertise,
        }),
      );
    } on Object {
      await stopGattServer();
      rethrow;
    }
  }

  Future<void> stopGattServer() async {
    final adapter = await _adapter();
    final advertisement = _advertisement;
    _advertisement = null;
    if (advertisement != null) {
      try {
        await adapter.callMethod(
          _advertisingManagerInterface,
          'UnregisterAdvertisement',
          [advertisement.path],
        );
      } on Object {
        // BlueZ may already have released the advertisement.
      }
      await _client.unregisterObject(advertisement);
    }
    final root = _gattRoot;
    final service = _localGattService;
    final characteristic = _localGattCharacteristic;
    _gattRoot = null;
    _localGattService = null;
    _localGattCharacteristic = null;
    if (root != null) {
      try {
        await adapter.callMethod(
          _gattManagerInterface,
          'UnregisterApplication',
          [root.path],
        );
      } on Object {
        // BlueZ may already have released the application.
      }
    }
    if (characteristic != null) {
      await _client.unregisterObject(characteristic);
    }
    if (service != null) await _client.unregisterObject(service);
    if (root != null) await _client.unregisterObject(root);
  }

  Future<int> notifyGattServer(Uint8List bytes) async {
    final characteristic = _localGattCharacteristic;
    if (characteristic == null) {
      throw StateError('bluetooth.gattServerNotRunning');
    }
    final subscribers = await characteristic.notify(bytes);
    _events.add(
      _event('data', {
        'transport': 'BLE Server',
        'direction': 'TX',
        'operation': 'notify',
        'bytes': bytes,
      }),
    );
    return subscribers;
  }

  Future<bool> read(String service, String characteristic) async {
    final value = await _characteristic(service, characteristic);
    final result = await value.callMethod(
      _characteristicInterface,
      'ReadValue',
      [DBusDict.stringVariant(const {})],
      replySignature: DBusSignature('ay'),
    );
    final bytes = Uint8List.fromList(
      result.values.first.asByteArray().toList(),
    );
    _events.add(
      _event('data', {
        'transport': 'BLE',
        'direction': 'RX',
        'operation': 'read',
        'status': 0,
        'characteristic': characteristic,
        'bytes': bytes,
      }),
    );
    return true;
  }

  Future<bool> write(
    String service,
    String characteristic,
    Uint8List bytes, {
    required bool withResponse,
  }) async {
    final value = await _characteristic(service, characteristic);
    await value.callMethod(_characteristicInterface, 'WriteValue', [
      DBusArray.byte(bytes),
      DBusDict.stringVariant({
        'type': DBusString(withResponse ? 'request' : 'command'),
      }),
    ]);
    _events.add(
      _event('bleWrite', {'status': 0, 'characteristic': characteristic}),
    );
    return true;
  }

  Future<bool> notify(
    String service,
    String characteristic,
    bool enable,
  ) async {
    final value = await _characteristic(service, characteristic);
    await value.callMethod(
      _characteristicInterface,
      enable ? 'StartNotify' : 'StopNotify',
      const [],
    );
    return true;
  }

  Future<DBusRemoteObject> _adapter() async {
    if (_adapterPath == null) await status();
    final path = _adapterPath;
    if (path == null) throw StateError('bluetooth.adapterMissing');
    return DBusRemoteObject(_client, name: _bluez, path: path);
  }

  Future<(DBusObjectPath, DBusRemoteObject)> _deviceByAddress(
    String address,
  ) async {
    final objects = await _manager.getManagedObjects();
    for (final entry in objects.entries) {
      final values = entry.value[_deviceInterface];
      if (_native<String>(values?['Address'])?.toUpperCase() ==
          address.toUpperCase()) {
        return (
          entry.key,
          DBusRemoteObject(_client, name: _bluez, path: entry.key),
        );
      }
    }
    throw StateError('bluetooth.deviceNotFound');
  }

  Future<DBusRemoteObject> _characteristic(
    String service,
    String characteristic,
  ) async {
    final objects = await _manager.getManagedObjects();
    for (final entry in objects.entries) {
      final values = entry.value[_characteristicInterface];
      if (values == null) continue;
      if (_native<String>(values['UUID'])?.toLowerCase() !=
          characteristic.toLowerCase())
        continue;
      final servicePath = _native<DBusObjectPath>(values['Service']);
      final serviceValues = servicePath == null
          ? null
          : objects[servicePath]?[_serviceInterface];
      if (_native<String>(serviceValues?['UUID'])?.toLowerCase() ==
          service.toLowerCase()) {
        return DBusRemoteObject(_client, name: _bluez, path: entry.key);
      }
    }
    throw StateError('bluetooth.characteristicNotFound');
  }

  Future<void> _emitGattTree() async {
    final objects = await _manager.getManagedObjects();
    final services = <Map<String, Object?>>[];
    for (final entry in objects.entries) {
      final values = entry.value[_serviceInterface];
      if (values == null) continue;
      final device = _native<DBusObjectPath>(values['Device']);
      if (_connectedDevice != null && device != _connectedDevice) continue;
      final characteristics = <Map<String, Object?>>[];
      for (final child in objects.entries) {
        final props = child.value[_characteristicInterface];
        if (props == null ||
            _native<DBusObjectPath>(props['Service']) != entry.key)
          continue;
        final flags = _stringList(props['Flags']);
        characteristics.add({
          'uuid': _native<String>(props['UUID']) ?? '',
          'properties': _androidProperties(flags),
          'permissions': 0,
          'descriptors': const <String>[],
        });
      }
      services.add({
        'uuid': _native<String>(values['UUID']) ?? '',
        'type': _native<bool>(values['Primary']) == true ? 0 : 1,
        'characteristics': characteristics,
      });
    }
    _events.add(_event('bleServices', {'status': 0, 'services': services}));
  }

  Future<void> _refreshDevices({required bool classic}) async {
    final objects = await _manager.getManagedObjects();
    for (final device in _devices(objects)) {
      final address = device['address']?.toString() ?? '';
      final fingerprint =
          '${device['rssi']}|${device['name']}|${device['connected']}|${device['services']}';
      if (_fingerprints[address] == fingerprint) continue;
      _fingerprints[address] = fingerprint;
      _events.add(_event(classic ? 'classicDevice' : 'bleDevice', device));
    }
  }

  Iterable<Map<Object?, Object?>> _devices(
    Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects,
  ) sync* {
    for (final entry in objects.entries) {
      final values = entry.value[_deviceInterface];
      if (values == null) continue;
      final address = _native<String>(values['Address']);
      if (address == null) continue;
      yield {
        'address': address,
        'name':
            _native<String>(values['Name']) ?? _native<String>(values['Alias']),
        'localName': _native<String>(values['Alias']),
        'rssi': _native<int>(values['RSSI']),
        'txPower': _native<int>(values['TxPower']),
        'bonded': _native<bool>(values['Paired']) ?? false,
        'bondState': _native<bool>(values['Paired']) == true ? 12 : 10,
        'connectable': true,
        'connected': _native<bool>(values['Connected']) ?? false,
        'services': _stringList(values['UUIDs']),
        'seenAt': DateTime.now().millisecondsSinceEpoch,
        'objectPath': entry.key.value,
      };
    }
  }

  Future<void> _ensureSubscription() async {
    if (_subscription != null) return;
    _subscription = _manager.signals.listen((signal) {
      if (signal is DBusPropertiesChangedSignal &&
          signal.propertiesInterface == _characteristicInterface &&
          signal.changedProperties.containsKey('Value')) {
        final bytes = signal.changedProperties['Value']?.asByteArray().toList();
        if (bytes != null) {
          _events.add(
            _event('data', {
              'transport': 'BLE',
              'direction': 'RX',
              'operation': 'notify',
              'characteristic': signal.path.value,
              'bytes': Uint8List.fromList(bytes),
            }),
          );
        }
      }
    });
  }

  (DBusObjectPath, Map<String, DBusValue>)? _findInterface(
    Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects,
    String interface,
  ) {
    for (final entry in objects.entries) {
      final values = entry.value[interface];
      if (values != null) return (entry.key, values);
    }
    return null;
  }

  static T? _native<T>(DBusValue? value) {
    if (value == null) return null;
    final native = value.toNative();
    return native is T ? native : null;
  }

  static List<String> _stringList(DBusValue? value) {
    final native = value?.toNative();
    return native is List
        ? native.whereType<String>().toList(growable: false)
        : const [];
  }

  static int _androidProperties(List<String> flags) {
    var result = 0;
    if (flags.contains('read')) result |= 0x02;
    if (flags.contains('write-without-response')) result |= 0x04;
    if (flags.contains('write')) result |= 0x08;
    if (flags.contains('notify')) result |= 0x10;
    if (flags.contains('indicate')) result |= 0x20;
    return result;
  }

  static Map<Object?, Object?> _event(
    String type,
    Map<Object?, Object?> values,
  ) => {'type': type, 'time': DateTime.now().millisecondsSinceEpoch, ...values};

  static Map<Object?, Object?> _failure(String code, String detail) => {
    'supported': false,
    'enabled': false,
    'errorCode': code,
    'technicalDetails': detail,
    'permissions': const {'scan': false, 'connect': false, 'advertise': false},
  };
}

class _BluezRfcommProfile extends DBusObject {
  _BluezRfcommProfile(
    super.path, {
    required this.onConnection,
    required this.onDisconnection,
    required this.onRelease,
  });

  static const _interface = 'org.bluez.Profile1';
  final Future<void> Function(DBusObjectPath, ResourceHandle) onConnection;
  final Future<void> Function(DBusObjectPath) onDisconnection;
  final void Function() onRelease;

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      _interface,
      methods: [
        DBusIntrospectMethod('Release'),
        DBusIntrospectMethod(
          'NewConnection',
          args: [
            DBusIntrospectArgument(
              DBusSignature('o'),
              DBusArgumentDirection.in_,
              name: 'device',
            ),
            DBusIntrospectArgument(
              DBusSignature('h'),
              DBusArgumentDirection.in_,
              name: 'fd',
            ),
            DBusIntrospectArgument(
              DBusSignature('a{sv}'),
              DBusArgumentDirection.in_,
              name: 'fd_properties',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'RequestDisconnection',
          args: [
            DBusIntrospectArgument(
              DBusSignature('o'),
              DBusArgumentDirection.in_,
              name: 'device',
            ),
          ],
        ),
      ],
    ),
  ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != _interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (call.name) {
      case 'Release':
        onRelease();
        return DBusMethodSuccessResponse();
      case 'NewConnection':
        if (call.values.length != 3 ||
            call.signature != DBusSignature('oha{sv}')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        await onConnection(
          call.values[0].asObjectPath(),
          call.values[1].asUnixFd(),
        );
        return DBusMethodSuccessResponse();
      case 'RequestDisconnection':
        if (call.values.length != 1 || call.signature != DBusSignature('o')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        await onDisconnection(call.values[0].asObjectPath());
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

class _BluezGattService extends DBusObject {
  _BluezGattService(super.path, {required this.uuid});

  static const interface = 'org.bluez.GattService1';
  final String uuid;

  Map<String, DBusValue> get _properties => {
    'UUID': DBusString(uuid),
    'Primary': const DBusBoolean(true),
    'Includes': DBusArray.objectPath(const []),
  };

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    interface: _properties,
  };

  @override
  Future<DBusMethodResponse> getAllProperties(String name) async =>
      name == interface
      ? DBusGetAllPropertiesResponse(_properties)
      : DBusMethodErrorResponse.unknownInterface();

  @override
  Future<DBusMethodResponse> getProperty(
    String interfaceName,
    String name,
  ) async {
    if (interfaceName != interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = _properties[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }
}

class _BluezGattCharacteristic extends DBusObject {
  _BluezGattCharacteristic(
    super.path, {
    required this.uuid,
    required this.servicePath,
    required this.onWrite,
  });

  static const interface = 'org.bluez.GattCharacteristic1';
  final String uuid;
  final DBusObjectPath servicePath;
  final void Function(Uint8List) onWrite;
  Uint8List _value = Uint8List(0);
  bool _notifying = false;

  Map<String, DBusValue> get _properties => {
    'UUID': DBusString(uuid),
    'Service': servicePath,
    'Value': DBusArray.byte(_value),
    'Notifying': DBusBoolean(_notifying),
    'Flags': DBusArray.string(const [
      'read',
      'write',
      'write-without-response',
      'notify',
    ]),
  };

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    interface: _properties,
  };

  @override
  Future<DBusMethodResponse> getAllProperties(String name) async =>
      name == interface
      ? DBusGetAllPropertiesResponse(_properties)
      : DBusMethodErrorResponse.unknownInterface();

  @override
  Future<DBusMethodResponse> getProperty(
    String interfaceName,
    String name,
  ) async {
    if (interfaceName != interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = _properties[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (call.name) {
      case 'ReadValue':
        if (call.values.length != 1 ||
            call.signature != DBusSignature('a{sv}')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        return DBusMethodSuccessResponse([DBusArray.byte(_value)]);
      case 'WriteValue':
        if (call.values.length != 2 ||
            call.signature != DBusSignature('aya{sv}')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        _value = Uint8List.fromList(call.values[0].asByteArray().toList());
        onWrite(_value);
        await emitPropertiesChanged(
          interface,
          changedProperties: {'Value': DBusArray.byte(_value)},
        );
        return DBusMethodSuccessResponse();
      case 'StartNotify':
        _notifying = true;
        await emitPropertiesChanged(
          interface,
          changedProperties: const {'Notifying': DBusBoolean(true)},
        );
        return DBusMethodSuccessResponse();
      case 'StopNotify':
        _notifying = false;
        await emitPropertiesChanged(
          interface,
          changedProperties: const {'Notifying': DBusBoolean(false)},
        );
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  Future<int> notify(Uint8List bytes) async {
    _value = Uint8List.fromList(bytes);
    await emitPropertiesChanged(
      interface,
      changedProperties: {'Value': DBusArray.byte(_value)},
    );
    return _notifying ? 1 : 0;
  }
}

class _BluezAdvertisement extends DBusObject {
  _BluezAdvertisement(super.path, {required this.serviceUuid});

  static const interface = 'org.bluez.LEAdvertisement1';
  final String serviceUuid;

  Map<String, DBusValue> get _properties => {
    'Type': const DBusString('peripheral'),
    'ServiceUUIDs': DBusArray.string([serviceUuid]),
    'LocalName': const DBusString('ProtoDeck'),
    'Includes': DBusArray.string(const ['tx-power']),
  };

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    interface: _properties,
  };

  @override
  Future<DBusMethodResponse> getAllProperties(String name) async =>
      name == interface
      ? DBusGetAllPropertiesResponse(_properties)
      : DBusMethodErrorResponse.unknownInterface();

  @override
  Future<DBusMethodResponse> getProperty(
    String interfaceName,
    String name,
  ) async {
    if (interfaceName != interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = _properties[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return call.name == 'Release'
        ? DBusMethodSuccessResponse()
        : DBusMethodErrorResponse.unknownMethod();
  }
}
