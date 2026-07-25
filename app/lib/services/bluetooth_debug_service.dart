import 'dart:io';

import 'package:flutter/services.dart';

class BluetoothDebugService {
  static const _channel = MethodChannel('nettools/native');
  static bool get _desktop => Platform.isWindows || Platform.isLinux;

  Future<Map<Object?, Object?>> status() async => _desktop
      ? {
          'supported': false,
          'enabled': false,
          'platform': Platform.operatingSystem,
          'reason': '${Platform.operatingSystem} 蓝牙 GATT/RFCOMM 原生适配器尚未接入',
          'permissions': const {'scan': false, 'connect': false},
        }
      : await _channel.invokeMapMethod<Object?, Object?>('bluetoothStatus') ??
            {};

  Future<List<Map<Object?, Object?>>> bondedDevices() async => _desktop
      ? const []
      : (await _channel.invokeListMethod<Object?>('bluetoothBonded') ??
                const [])
            .whereType<Map<Object?, Object?>>()
            .toList(growable: false);

  Future<Map<Object?, Object?>?> pollEvent() => _desktop
      ? Future.value()
      : _channel.invokeMapMethod<Object?, Object?>('bluetoothPollEvent');

  Future<void> startClassicScan() =>
      _channel.invokeMethod<void>('classicScanStart');
  Future<void> stopClassicScan() =>
      _channel.invokeMethod<void>('classicScanStop');
  Future<void> connectClassic(String address, String uuid) => _channel
      .invokeMethod<void>('classicConnect', {'address': address, 'uuid': uuid});
  Future<void> startClassicServer(String name, String uuid) => _channel
      .invokeMethod<void>('classicServerStart', {'name': name, 'uuid': uuid});
  Future<void> sendClassic(Uint8List bytes) =>
      _channel.invokeMethod<void>('classicSend', {'bytes': bytes});
  Future<void> stopClassic() => _channel.invokeMethod<void>('classicStop');

  Future<void> startBleScan() => _channel.invokeMethod<void>('bleScanStart');
  Future<void> stopBleScan() => _channel.invokeMethod<void>('bleScanStop');
  Future<void> connectBle(String address, {bool autoConnect = false}) =>
      _channel.invokeMethod<void>('bleConnect', {
        'address': address,
        'autoConnect': autoConnect,
      });
  Future<void> disconnectBle() => _channel.invokeMethod<void>('bleDisconnect');
  Future<bool> requestMtu(int mtu) async =>
      await _channel.invokeMethod<bool>('bleRequestMtu', {'mtu': mtu}) ?? false;
  Future<bool> readRemoteRssi() async =>
      await _channel.invokeMethod<bool>('bleReadRssi') ?? false;
  Future<bool> setConnectionPriority(int priority) async =>
      await _channel.invokeMethod<bool>('bleConnectionPriority', {
        'priority': priority,
      }) ??
      false;
  Future<bool> readBle(String service, String characteristic) async =>
      await _channel.invokeMethod<bool>('bleRead', {
        'service': service,
        'characteristic': characteristic,
      }) ??
      false;
  Future<bool> writeBle(
    String service,
    String characteristic,
    Uint8List bytes, {
    bool withResponse = true,
  }) async =>
      await _channel.invokeMethod<bool>('bleWrite', {
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
  ) async =>
      await _channel.invokeMethod<bool>('bleNotify', {
        'service': service,
        'characteristic': characteristic,
        'enable': enable,
      }) ??
      false;
  Future<void> startBleServer(
    String service,
    String characteristic, {
    bool advertise = true,
  }) => _channel.invokeMethod<void>('bleServerStart', {
    'service': service,
    'characteristic': characteristic,
    'advertise': advertise,
  });
  Future<void> stopBleServer() => _channel.invokeMethod<void>('bleServerStop');
  Future<int> notifyBleServer(Uint8List bytes) async =>
      await _channel.invokeMethod<int>('bleServerNotify', {'bytes': bytes}) ??
      0;
}
