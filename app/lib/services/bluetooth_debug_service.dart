import 'dart:io';

import 'package:flutter/services.dart';

import 'linux_bluez_service.dart';

class BluetoothDebugService {
  static const _channel = MethodChannel('nettools/native');
  static final LinuxBluezService _linux = LinuxBluezService();

  Future<Map<Object?, Object?>> status() async => Platform.isLinux
      ? _linux.status()
      : await _channel.invokeMapMethod<Object?, Object?>('bluetoothStatus') ??
            {};

  Future<List<Map<Object?, Object?>>> bondedDevices() async => Platform.isLinux
      ? _linux.bondedDevices()
      : (await _channel.invokeListMethod<Object?>('bluetoothBonded') ??
                const [])
            .whereType<Map<Object?, Object?>>()
            .toList(growable: false);

  Future<Map<Object?, Object?>?> pollEvent() => Platform.isLinux
      ? _linux.pollEvent()
      : _channel.invokeMapMethod<Object?, Object?>('bluetoothPollEvent');

  Future<void> startClassicScan() => Platform.isLinux
      ? _linux.startDiscovery(classic: true)
      : _channel.invokeMethod<void>('classicScanStart');
  Future<void> stopClassicScan() => Platform.isLinux
      ? _linux.stopDiscovery(classic: true)
      : _channel.invokeMethod<void>('classicScanStop');
  Future<void> connectClassic(String address, String uuid) => Platform.isLinux
      ? _linux.connectClassic(address, uuid)
      : _channel.invokeMethod<void>('classicConnect', {
          'address': address,
          'uuid': uuid,
        });
  Future<void> startClassicServer(String name, String uuid) => Platform.isLinux
      ? _linux.startClassicServer(name, uuid)
      : _channel.invokeMethod<void>('classicServerStart', {
          'name': name,
          'uuid': uuid,
        });
  Future<void> sendClassic(Uint8List bytes) => Platform.isLinux
      ? _linux.sendClassic(bytes)
      : _channel.invokeMethod<void>('classicSend', {'bytes': bytes});
  Future<void> stopClassic() => Platform.isLinux
      ? _linux.stopClassic()
      : _channel.invokeMethod<void>('classicStop');

  Future<void> startBleScan() => Platform.isLinux
      ? _linux.startDiscovery(classic: false)
      : _channel.invokeMethod<void>('bleScanStart');
  Future<void> stopBleScan() => Platform.isLinux
      ? _linux.stopDiscovery(classic: false)
      : _channel.invokeMethod<void>('bleScanStop');
  Future<void> connectBle(String address, {bool autoConnect = false}) =>
      Platform.isLinux
      ? _linux.connectBle(address)
      : _channel.invokeMethod<void>('bleConnect', {
          'address': address,
          'autoConnect': autoConnect,
        });
  Future<void> disconnectBle() => Platform.isLinux
      ? _linux.disconnectBle()
      : _channel.invokeMethod<void>('bleDisconnect');
  Future<bool> requestMtu(int mtu) async => Platform.isLinux
      ? false
      : await _channel.invokeMethod<bool>('bleRequestMtu', {'mtu': mtu}) ??
            false;
  Future<bool> readRemoteRssi() async => Platform.isLinux
      ? false
      : await _channel.invokeMethod<bool>('bleReadRssi') ?? false;
  Future<bool> setConnectionPriority(int priority) async =>
      await _channel.invokeMethod<bool>('bleConnectionPriority', {
        'priority': priority,
      }) ??
      false;
  Future<bool> readBle(String service, String characteristic) async =>
      Platform.isLinux
      ? _linux.read(service, characteristic)
      : await _channel.invokeMethod<bool>('bleRead', {
              'service': service,
              'characteristic': characteristic,
            }) ??
            false;
  Future<bool> writeBle(
    String service,
    String characteristic,
    Uint8List bytes, {
    bool withResponse = true,
  }) async => Platform.isLinux
      ? _linux.write(service, characteristic, bytes, withResponse: withResponse)
      : await _channel.invokeMethod<bool>('bleWrite', {
              'service': service,
              'characteristic': characteristic,
              'bytes': bytes,
              'withResponse': withResponse,
            }) ??
            false;
  Future<bool> notifyBle(
    String service,
    String characteristic,
    bool enable,
  ) async => Platform.isLinux
      ? _linux.notify(service, characteristic, enable)
      : await _channel.invokeMethod<bool>('bleNotify', {
              'service': service,
              'characteristic': characteristic,
              'enable': enable,
            }) ??
            false;
  Future<void> startBleServer(
    String service,
    String characteristic, {
    bool advertise = true,
  }) => Platform.isLinux
      ? _linux.startGattServer(service, characteristic, advertise: advertise)
      : _channel.invokeMethod<void>('bleServerStart', {
          'service': service,
          'characteristic': characteristic,
          'advertise': advertise,
        });
  Future<void> stopBleServer() => Platform.isLinux
      ? _linux.stopGattServer()
      : _channel.invokeMethod<void>('bleServerStop');
  Future<int> notifyBleServer(Uint8List bytes) async => Platform.isLinux
      ? _linux.notifyGattServer(bytes)
      : await _channel.invokeMethod<int>('bleServerNotify', {'bytes': bytes}) ??
            0;
}
