package com.nettools.nettools_mobile

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid
import android.location.LocationManager
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors

@SuppressLint("MissingPermission")
class BluetoothDebugManager(private val context: Context) {
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? get() = manager.adapter
    private val executor = Executors.newCachedThreadPool()
    private val events = ConcurrentLinkedQueue<Map<String, Any?>>()
    private var classicSocket: BluetoothSocket? = null
    private var classicServer: BluetoothServerSocket? = null
    private var bleGatt: BluetoothGatt? = null
    private var gattServer: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private val gattServerDevices = CopyOnWriteArraySet<BluetoothDevice>()
    private var gattServerCharacteristic: BluetoothGattCharacteristic? = null
    private var classicReceiverRegistered = false
    private var bleScanning = false

    fun status(): Map<String, Any?> = mapOf(
        "supported" to (adapter != null),
        "enabled" to (adapter?.isEnabled == true),
        "name" to if (hasConnectPermission()) adapter?.name else null,
        "address" to if (hasConnectPermission()) adapter?.address else null,
        "ble" to context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE),
        "advertising" to (adapter?.isMultipleAdvertisementSupported == true),
        "extendedAdvertising" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && adapter?.isLeExtendedAdvertisingSupported == true),
        "locationEnabled" to ((context.getSystemService(Context.LOCATION_SERVICE) as LocationManager).isLocationEnabled),
        "apiLevel" to Build.VERSION.SDK_INT,
        "permissions" to mapOf(
            "scan" to hasScanPermission(),
            "connect" to hasConnectPermission(),
            "advertise" to hasAdvertisePermission(),
        ),
    )

    fun bondedDevices(): List<Map<String, Any?>> {
        requireConnect()
        return adapter?.bondedDevices.orEmpty().map(::deviceMap).sortedBy { it["name"] as? String ?: "" }
    }

    fun pollEvent(): Map<String, Any?>? = events.poll()

    fun startClassicScan(): Boolean {
        requireScan()
        val value = adapter ?: error("设备不支持蓝牙")
        if (!classicReceiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
                addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            }
            context.registerReceiver(classicReceiver, filter)
            classicReceiverRegistered = true
        }
        value.cancelDiscovery()
        emit("classicScan", mapOf("state" to "started"))
        return value.startDiscovery()
    }

    fun stopClassicScan() {
        if (hasScanPermission()) adapter?.cancelDiscovery()
    }

    fun connectClassic(address: String, uuid: String) {
        requireConnect()
        val device = adapter?.getRemoteDevice(address) ?: error("设备不支持蓝牙")
        val serviceUuid = UUID.fromString(uuid)
        stopClassic()
        executor.execute {
            runCatching {
                if (hasScanPermission()) adapter?.cancelDiscovery()
                val socket = device.createRfcommSocketToServiceRecord(serviceUuid)
                socket.connect()
                classicSocket = socket
                emit("classicConnection", mapOf("state" to "connected", "peer" to address))
                readClassic(socket.inputStream, address)
            }.onFailure {
                emit("error", mapOf("scope" to "classic", "message" to (it.message ?: it.toString())))
                stopClassic()
            }
        }
    }

    fun startClassicServer(name: String, uuid: String) {
        requireConnect()
        stopClassic()
        val serviceUuid = UUID.fromString(uuid)
        classicServer = adapter?.listenUsingRfcommWithServiceRecord(name, serviceUuid)
            ?: error("无法启动 RFCOMM Server")
        emit("classicServer", mapOf("state" to "listening", "uuid" to uuid))
        executor.execute {
            runCatching {
                val socket = classicServer?.accept() ?: return@runCatching
                classicSocket = socket
                val peer = socket.remoteDevice.address
                emit("classicConnection", mapOf("state" to "connected", "peer" to peer))
                readClassic(socket.inputStream, peer)
            }.onFailure {
                emit("error", mapOf("scope" to "classicServer", "message" to (it.message ?: it.toString())))
            }
        }
    }

    fun sendClassic(bytes: ByteArray) {
        val socket = classicSocket ?: error("RFCOMM 尚未连接")
        socket.outputStream.write(bytes)
        socket.outputStream.flush()
        emit("data", mapOf("transport" to "BT", "direction" to "TX", "bytes" to bytes))
    }

    fun stopClassic() {
        runCatching { classicSocket?.close() }
        runCatching { classicServer?.close() }
        classicSocket = null
        classicServer = null
    }

    fun startBleScan() {
        requireScan()
        val scanner = adapter?.bluetoothLeScanner ?: error("BLE 扫描不可用，请确认蓝牙已开启")
        if (bleScanning) return
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setReportDelay(0)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                    setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
                    setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                }
            }
            .build()
        // Keep Android's legacy/1M defaults. Forcing extended PHY scanning is a
        // common reason that otherwise visible earbuds, routers and sensors do
        // not produce callbacks on vendor Bluetooth stacks.
        scanner.startScan(emptyList<ScanFilter>(), settings, bleScanCallback)
        bleScanning = true
        emit("bleScan", mapOf("state" to "started", "mode" to "lowLatency", "filters" to 0))
    }

    fun stopBleScan() {
        if (hasScanPermission()) adapter?.bluetoothLeScanner?.stopScan(bleScanCallback)
        bleScanning = false
        emit("bleScan", mapOf("state" to "stopped"))
    }

    fun connectBle(address: String, autoConnect: Boolean) {
        requireConnect()
        bleGatt?.close()
        val device = adapter?.getRemoteDevice(address) ?: error("BLE 设备不存在")
        bleGatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(context, autoConnect, bleCallback, BluetoothDevice.TRANSPORT_LE)
        } else {
            device.connectGatt(context, autoConnect, bleCallback)
        }
        emit("bleConnection", mapOf("state" to "connecting", "peer" to address))
    }

    fun disconnectBle() {
        if (hasConnectPermission()) bleGatt?.disconnect()
        bleGatt?.close()
        bleGatt = null
    }

    fun requestBleMtu(mtu: Int): Boolean {
        requireConnect()
        require(mtu in 23..517) { "ATT MTU 必须为 23～517" }
        return bleGatt?.requestMtu(mtu) ?: error("BLE 尚未连接")
    }

    fun readBleRssi(): Boolean {
        requireConnect()
        return bleGatt?.readRemoteRssi() ?: error("BLE 尚未连接")
    }

    fun setBleConnectionPriority(priority: Int): Boolean {
        requireConnect()
        require(priority in BluetoothGatt.CONNECTION_PRIORITY_BALANCED..BluetoothGatt.CONNECTION_PRIORITY_LOW_POWER) {
            "连接优先级参数无效"
        }
        return bleGatt?.requestConnectionPriority(priority) ?: error("BLE 尚未连接")
    }

    fun readBle(serviceUuid: String, characteristicUuid: String): Boolean {
        requireConnect()
        val characteristic = characteristic(serviceUuid, characteristicUuid)
        return bleGatt?.readCharacteristic(characteristic) ?: false
    }

    fun writeBle(serviceUuid: String, characteristicUuid: String, bytes: ByteArray, withResponse: Boolean): Boolean {
        requireConnect()
        val gatt = bleGatt ?: error("BLE 尚未连接")
        val characteristic = characteristic(serviceUuid, characteristicUuid)
        characteristic.writeType = if (withResponse) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        }
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(characteristic, bytes, characteristic.writeType) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = bytes
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(characteristic)
        }
        if (started) emit("data", mapOf("transport" to "BLE", "direction" to "TX", "bytes" to bytes, "characteristic" to characteristicUuid))
        return started
    }

    fun setBleNotify(serviceUuid: String, characteristicUuid: String, enable: Boolean): Boolean {
        requireConnect()
        val gatt = bleGatt ?: error("BLE 尚未连接")
        val characteristic = characteristic(serviceUuid, characteristicUuid)
        val local = gatt.setCharacteristicNotification(characteristic, enable)
        val descriptor = characteristic.getDescriptor(CCCD_UUID)
        if (descriptor != null) {
            val value = if (enable) BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE else BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeDescriptor(descriptor, value)
            } else {
                @Suppress("DEPRECATION")
                descriptor.value = value
                @Suppress("DEPRECATION")
                gatt.writeDescriptor(descriptor)
            }
        }
        return local
    }

    fun startBleServer(serviceText: String, characteristicText: String, advertise: Boolean) {
        requireConnect()
        if (advertise) requireAdvertise()
        stopBleServer()
        val serviceUuid = UUID.fromString(serviceText)
        val characteristicUuid = UUID.fromString(characteristicText)
        gattServer = manager.openGattServer(context, gattServerCallback)
        val service = BluetoothGattService(serviceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val characteristic = BluetoothGattCharacteristic(
            characteristicUuid,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ or BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        characteristic.value = ByteArray(0)
        gattServerCharacteristic = characteristic
        characteristic.addDescriptor(
            BluetoothGattDescriptor(
                CCCD_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
            ),
        )
        service.addCharacteristic(characteristic)
        check(gattServer?.addService(service) == true) { "GATT Service 添加失败" }
        if (advertise) {
            val callback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                    emit("bleServer", mapOf("state" to "advertising", "service" to serviceText))
                }
                override fun onStartFailure(errorCode: Int) {
                    emit("error", mapOf("scope" to "bleAdvertise", "message" to "广播启动失败：$errorCode"))
                }
            }
            advertiseCallback = callback
            advertiser = adapter?.bluetoothLeAdvertiser
            advertiser?.startAdvertising(
                AdvertiseSettings.Builder().setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                    .setConnectable(true).setTimeout(0).build(),
                AdvertiseData.Builder().setIncludeDeviceName(true).addServiceUuid(ParcelUuid(serviceUuid)).build(),
                callback,
            ) ?: error("设备不支持 BLE 广播")
        } else {
            emit("bleServer", mapOf("state" to "started", "service" to serviceText))
        }
    }

    fun stopBleServer() {
        if (hasAdvertisePermission()) advertiseCallback?.let { advertiser?.stopAdvertising(it) }
        advertiseCallback = null
        advertiser = null
        runCatching { gattServer?.close() }
        gattServer = null
        gattServerCharacteristic = null
        gattServerDevices.clear()
    }

    fun notifyBleServer(bytes: ByteArray): Int {
        requireConnect()
        val server = gattServer ?: error("GATT Server 尚未启动")
        val characteristic = gattServerCharacteristic ?: error("GATT Characteristic 未就绪")
        if (gattServerDevices.isEmpty()) error("尚无 BLE Central 连接")
        var success = 0
        for (device in gattServerDevices) {
            val sent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                server.notifyCharacteristicChanged(device, characteristic, false, bytes) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                characteristic.value = bytes
                @Suppress("DEPRECATION")
                server.notifyCharacteristicChanged(device, characteristic, false)
            }
            if (sent) success++
        }
        emit("data", mapOf("transport" to "BLE Server", "direction" to "TX", "bytes" to bytes, "clients" to success))
        return success
    }

    fun dispose() {
        stopClassicScan()
        stopBleScan()
        stopClassic()
        disconnectBle()
        stopBleServer()
        if (classicReceiverRegistered) runCatching { context.unregisterReceiver(classicReceiver) }
        classicReceiverRegistered = false
    }

    private fun characteristic(serviceUuid: String, characteristicUuid: String): BluetoothGattCharacteristic {
        return bleGatt?.getService(UUID.fromString(serviceUuid))?.getCharacteristic(UUID.fromString(characteristicUuid))
            ?: error("未找到指定 Characteristic")
    }

    private fun readClassic(input: InputStream, peer: String) {
        val buffer = ByteArray(4096)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (count > 0) emit("data", mapOf("transport" to "BT", "direction" to "RX", "peer" to peer, "bytes" to buffer.copyOf(count)))
        }
        emit("classicConnection", mapOf("state" to "disconnected", "peer" to peer))
    }

    private val classicReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }
                    if (device != null) emit("classicDevice", deviceMap(device) + mapOf("rssi" to intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, 0).toInt()))
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> emit("classicScan", mapOf("state" to "finished"))
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> emit("bond", mapOf("state" to "changed"))
            }
        }
    }

    private val bleScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            bleScanning = true
            emitBleResult(callbackType, result)
        }
        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            results.forEach { emitBleResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
        }
        override fun onScanFailed(errorCode: Int) {
            bleScanning = false
            val message = when (errorCode) {
                SCAN_FAILED_ALREADY_STARTED -> "扫描已经启动"
                SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> "系统蓝牙扫描注册失败，请关闭再开启蓝牙"
                SCAN_FAILED_FEATURE_UNSUPPORTED -> "设备不支持当前 BLE 扫描模式"
                SCAN_FAILED_INTERNAL_ERROR -> "Android 蓝牙栈内部错误"
                SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES -> "蓝牙硬件扫描资源不足"
                SCAN_FAILED_SCANNING_TOO_FREQUENTLY -> "扫描启动过于频繁，请稍后重试"
                else -> "未知错误"
            }
            emit("error", mapOf("scope" to "bleScan", "code" to errorCode, "message" to "BLE 扫描失败：$message ($errorCode)"))
        }
    }

    private fun emitBleResult(callbackType: Int, result: ScanResult) {
        val record = result.scanRecord
        val manufacturerData = record?.manufacturerSpecificData?.let { data ->
            (0 until data.size()).map { index ->
                mapOf("id" to data.keyAt(index), "bytes" to data.valueAt(index))
            }
        } ?: emptyList()
        val serviceData = record?.serviceData?.entries?.map { entry ->
            mapOf("uuid" to entry.key.uuid.toString(), "bytes" to entry.value)
        } ?: emptyList()
        val details = mutableMapOf<String, Any?>(
            "rssi" to result.rssi,
            "connectable" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) result.isConnectable else true,
            "services" to (record?.serviceUuids?.map { it.uuid.toString() } ?: emptyList<String>()),
            "localName" to record?.deviceName,
            "txPower" to record?.txPowerLevel?.takeUnless { it == Int.MIN_VALUE },
            "advertiseFlags" to record?.advertiseFlags,
            "manufacturerData" to manufacturerData,
            "serviceData" to serviceData,
            "rawBytes" to record?.bytes,
            "callbackType" to callbackType,
            "timestampNanos" to result.timestampNanos,
            "seenAt" to System.currentTimeMillis(),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            details["primaryPhy"] = result.primaryPhy
            details["secondaryPhy"] = result.secondaryPhy
            details["advertisingSid"] = result.advertisingSid.takeUnless { it == ScanResult.SID_NOT_PRESENT }
            details["periodicInterval"] = result.periodicAdvertisingInterval.takeUnless { it == 0 }
            details["dataStatus"] = result.dataStatus
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            details["serviceSolicitationUuids"] = record?.serviceSolicitationUuids?.map { it.uuid.toString() } ?: emptyList<String>()
        }
        emit("bleDevice", deviceMap(result.device) + details)
    }

    private val bleCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            val state = when (newState) {
                BluetoothProfile.STATE_CONNECTED -> "connected"
                BluetoothProfile.STATE_CONNECTING -> "connecting"
                BluetoothProfile.STATE_DISCONNECTING -> "disconnecting"
                else -> "disconnected"
            }
            emit("bleConnection", mapOf("state" to state, "status" to status, "peer" to gatt.device.address))
            if (newState == BluetoothProfile.STATE_CONNECTED) gatt.discoverServices()
        }
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val services = gatt.services.map { service ->
                mapOf(
                    "uuid" to service.uuid.toString(),
                    "type" to service.type,
                    "characteristics" to service.characteristics.map { value ->
                        mapOf(
                            "uuid" to value.uuid.toString(),
                            "properties" to value.properties,
                            "permissions" to value.permissions,
                            "descriptors" to value.descriptors.map { it.uuid.toString() },
                        )
                    },
                )
            }
            emit("bleServices", mapOf("status" to status, "services" to services))
        }
        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            emit("data", mapOf("transport" to "BLE", "direction" to "RX", "operation" to "read", "status" to status, "characteristic" to characteristic.uuid.toString(), "bytes" to value))
        }
        @Deprecated("Deprecated in Java")
        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) emit("data", mapOf("transport" to "BLE", "direction" to "RX", "operation" to "read", "status" to status, "characteristic" to characteristic.uuid.toString(), "bytes" to characteristic.value))
        }
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            emit("data", mapOf("transport" to "BLE", "direction" to "RX", "operation" to "notify", "characteristic" to characteristic.uuid.toString(), "bytes" to value))
        }
        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) emit("data", mapOf("transport" to "BLE", "direction" to "RX", "operation" to "notify", "characteristic" to characteristic.uuid.toString(), "bytes" to characteristic.value))
        }
        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            emit("bleWrite", mapOf("status" to status, "characteristic" to characteristic.uuid.toString()))
        }
        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            emit("bleMtu", mapOf("mtu" to mtu, "status" to status))
        }
        override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
            emit("bleRssi", mapOf("rssi" to rssi, "status" to status))
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) gattServerDevices.add(device)
            if (newState == BluetoothProfile.STATE_DISCONNECTED) gattServerDevices.remove(device)
            emit("bleServerConnection", mapOf("peer" to device.address, "status" to status, "state" to newState))
        }
        override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) {
            val value = characteristic.value ?: ByteArray(0)
            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, if (offset < value.size) value.copyOfRange(offset, value.size) else ByteArray(0))
        }
        override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) {
            characteristic.value = value
            emit("data", mapOf("transport" to "BLE Server", "direction" to "RX", "peer" to device.address, "characteristic" to characteristic.uuid.toString(), "bytes" to value))
            if (responseNeeded) gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
        }
    }

    private fun deviceMap(device: BluetoothDevice): Map<String, Any?> = mapOf(
        "address" to device.address,
        "name" to (if (hasConnectPermission()) device.name else null),
        "bondState" to (if (hasConnectPermission()) device.bondState else BluetoothDevice.BOND_NONE),
        "type" to (if (hasConnectPermission()) device.type else BluetoothDevice.DEVICE_TYPE_UNKNOWN),
    )

    private fun emit(type: String, data: Map<String, Any?>) {
        events.add(mapOf("type" to type, "time" to System.currentTimeMillis()) + data)
        while (events.size > 1000) events.poll()
    }

    private fun hasScanPermission() = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
    private fun hasConnectPermission() = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    private fun hasAdvertisePermission() = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || context.checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
    private fun requireScan() = check(hasScanPermission()) { "缺少附近设备扫描权限" }
    private fun requireConnect() = check(hasConnectPermission()) { "缺少蓝牙连接权限" }
    private fun requireAdvertise() = check(hasAdvertisePermission()) { "缺少蓝牙广播权限" }

    companion object {
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
