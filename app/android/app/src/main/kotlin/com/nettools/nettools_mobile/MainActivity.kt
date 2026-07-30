package com.nettools.nettools_mobile

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.ScanResult
import android.net.wifi.WifiInfo
import android.net.wifi.WifiAvailableChannel
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.net.wifi.rtt.RangingRequest
import android.net.wifi.rtt.RangingResult
import android.net.wifi.rtt.RangingResultCallback
import android.net.wifi.rtt.WifiRttManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.provider.Settings
import android.net.Uri
import android.telephony.CellIdentityLte
import android.telephony.CellIdentityNr
import android.telephony.CellInfo
import android.telephony.CellInfoCdma
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoTdscdma
import android.telephony.CellInfoWcdma
import android.telephony.CellSignalStrengthNr
import android.telephony.CellSignalStrengthTdscdma
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.net.Inet4Address
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

class MainActivity : FlutterActivity() {
    private data class PendingDocumentSave(
        val sourcePath: String,
        val result: MethodChannel.Result,
    )

    private companion object {
        const val REQUEST_CREATE_DOCUMENT = 0x5044
    }

    private val executor = Executors.newCachedThreadPool()
    @Volatile private var tracerouteCancelled = false
    @Volatile private var activeTracerouteProcess: Process? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    @Volatile private var lastWifiScanResults: List<ScanResult> = emptyList()
    private val bluetoothDebug by lazy { BluetoothDebugManager(applicationContext) }
    private val networkEventMonitor by lazy { NetworkEventMonitor(applicationContext) }
    private var pendingDocumentSave: PendingDocumentSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nettools/network_events",
        ).setStreamHandler(networkEventMonitor)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nettools/native",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNetworkContext" -> runCatching { getNetworkContext() }
                    .onSuccess(result::success)
                    .onFailure { result.error("NETWORK_CONTEXT", it.message, null) }
                "getTrafficSnapshot" -> runAsync(result) { TrafficSnapshotProvider.snapshot() }
                "hasUsageStatsAccess" -> result.success(TrafficSnapshotProvider.hasUsageAccess(this))
                "getAppTrafficStats" -> runAsync(result) {
                    TrafficSnapshotProvider.appTraffic(
                        this,
                        call.argument<Long>("sinceMs") ?: (System.currentTimeMillis() - 3_600_000L),
                    )
                }
                "openUsageStatsSettings" -> runCatching {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:$packageName")))
                    true
                }.onSuccess(result::success)
                    .onFailure { result.error("USAGE_SETTINGS", it.message, null) }
                "scanWifi" -> scanWifi(result)
                "requestWifiConnection" -> runCatching { requestWifiConnection(call) }
                    .onSuccess(result::success)
                    .onFailure { result.error("WIFI_CONNECTION", it.message, null) }
                "runWifiRtt" -> runWifiRtt(call, result)
                "runPing" -> runAsync(result) { runPing(call) }
                "probePathMtu" -> runAsync(result) { probePathMtu(call) }
                "runTraceroute" -> runAsync(result) { runTraceroute(call) }
                "runIperf" -> runAsync(result) {
                    val arguments = call.argument<List<String>>("arguments") ?: emptyList()
                    IperfNative.run(arguments.toTypedArray())
                }
                "stopIperf" -> runCatching { IperfNative.stop() }
                    .onSuccess(result::success)
                    .onFailure { result.error("IPERF_STOP", it.message, null) }
                "isIperfRunning" -> runCatching { IperfNative.isRunning() }
                    .onSuccess(result::success)
                    .onFailure { result.error("IPERF_STATE", it.message, null) }
                "pollIperfEvent" -> runCatching { IperfNative.pollEvent() }
                    .onSuccess(result::success)
                    .onFailure { result.error("IPERF_EVENT", it.message, null) }
                "smbConnect" -> runAsync(result) {
                    @Suppress("UNCHECKED_CAST")
                    SmbManager.connect(call.arguments as? Map<String, Any?> ?: emptyMap())
                }
                "smbList" -> runAsync(result) {
                    SmbManager.list(
                        call.argument<String>("sessionId").orEmpty(),
                        call.argument<String>("path").orEmpty(),
                    )
                }
                "smbMkdir" -> runAsync(result) {
                    SmbManager.mkdir(
                        call.argument<String>("sessionId").orEmpty(),
                        call.argument<String>("path").orEmpty(),
                    )
                    true
                }
                "smbDelete" -> runAsync(result) {
                    SmbManager.delete(
                        call.argument<String>("sessionId").orEmpty(),
                        call.argument<String>("path").orEmpty(),
                        call.argument<Boolean>("directory") ?: false,
                    )
                    true
                }
                "smbRename" -> runAsync(result) {
                    SmbManager.rename(
                        call.argument<String>("sessionId").orEmpty(),
                        call.argument<String>("oldPath").orEmpty(),
                        call.argument<String>("newPath").orEmpty(),
                    )
                    true
                }
                "smbUpload" -> runAsync(result) {
                    SmbManager.upload(
                        call.argument<String>("sessionId").orEmpty(),
                        call.argument<String>("localPath").orEmpty(),
                        call.argument<String>("remotePath").orEmpty(),
                    )
                }
                "smbDownload" -> runAsync(result) {
                    SmbManager.download(
                        call.argument<String>("sessionId").orEmpty(),
                        call.argument<String>("remotePath").orEmpty(),
                        call.argument<String>("localPath").orEmpty(),
                    )
                }
                "smbDisconnect" -> runAsync(result) {
                    SmbManager.disconnect(call.argument<String>("sessionId").orEmpty())
                }
                "bluetoothStatus" -> runCatching { bluetoothDebug.status() }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "bluetoothBonded" -> runCatching { bluetoothDebug.bondedDevices() }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "bluetoothPollEvent" -> result.success(bluetoothDebug.pollEvent())
                "classicScanStart" -> runCatching { bluetoothDebug.startClassicScan() }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "classicScanStop" -> { bluetoothDebug.stopClassicScan(); result.success(true) }
                "classicConnect" -> runCatching {
                    bluetoothDebug.connectClassic(call.argument<String>("address").orEmpty(), call.argument<String>("uuid").orEmpty()); true
                }.onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "classicServerStart" -> runCatching {
                    bluetoothDebug.startClassicServer(call.argument<String>("name") ?: "ProtoDeck RFCOMM", call.argument<String>("uuid").orEmpty()); true
                }.onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "classicSend" -> runCatching { bluetoothDebug.sendClassic(call.argument<ByteArray>("bytes") ?: byteArrayOf()); true }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "classicStop" -> { bluetoothDebug.stopClassic(); result.success(true) }
                "bleScanStart" -> runCatching { bluetoothDebug.startBleScan(); true }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "bleScanStop" -> { bluetoothDebug.stopBleScan(); result.success(true) }
                "bleConnect" -> runCatching {
                    bluetoothDebug.connectBle(call.argument<String>("address").orEmpty(), call.argument<Boolean>("autoConnect") ?: false); true
                }.onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "bleDisconnect" -> { bluetoothDebug.disconnectBle(); result.success(true) }
                "bleRequestMtu" -> runCatching { bluetoothDebug.requestBleMtu(call.argument<Int>("mtu") ?: 247) }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "bleReadRssi" -> runCatching { bluetoothDebug.readBleRssi() }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "bleConnectionPriority" -> runCatching { bluetoothDebug.setBleConnectionPriority(call.argument<Int>("priority") ?: 0) }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "bleRead" -> runCatching { bluetoothDebug.readBle(call.argument<String>("service").orEmpty(), call.argument<String>("characteristic").orEmpty()) }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "bleWrite" -> runCatching { bluetoothDebug.writeBle(call.argument<String>("service").orEmpty(), call.argument<String>("characteristic").orEmpty(), call.argument<ByteArray>("bytes") ?: byteArrayOf(), call.argument<Boolean>("withResponse") ?: true) }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "bleNotify" -> runCatching { bluetoothDebug.setBleNotify(call.argument<String>("service").orEmpty(), call.argument<String>("characteristic").orEmpty(), call.argument<Boolean>("enable") ?: true) }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "bleServerStart" -> runCatching { bluetoothDebug.startBleServer(call.argument<String>("service").orEmpty(), call.argument<String>("characteristic").orEmpty(), call.argument<Boolean>("advertise") ?: true); true }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "bleServerStop" -> { bluetoothDebug.stopBleServer(); result.success(true) }
                "bleServerNotify" -> runCatching { bluetoothDebug.notifyBleServer(call.argument<ByteArray>("bytes") ?: byteArrayOf()) }
                    .onSuccess(result::success).onFailure { result.error("BLUETOOTH", it.message, null) }
                "acquireMulticastLock" -> runCatching {
                    val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    multicastLock?.takeIf { it.isHeld }?.release()
                    multicastLock = manager.createMulticastLock("nettools-local-discovery").apply {
                        setReferenceCounted(false)
                        acquire()
                    }
                    true
                }.onSuccess(result::success)
                    .onFailure { result.error("MULTICAST_LOCK", it.message, null) }
                "releaseMulticastLock" -> {
                    runCatching { multicastLock?.takeIf { it.isHeld }?.release() }
                    multicastLock = null
                    result.success(true)
                }
                "cancelTraceroute" -> {
                    tracerouteCancelled = true
                    activeTracerouteProcess?.destroy()
                    result.success(true)
                }
                "startForegroundTask" -> runCatching {
                    NetworkTaskService.start(
                        this,
                        call.argument<String>("title") ?: "网络任务运行中",
                        call.argument<String>("detail") ?: "点击返回 ProtoDeck",
                    )
                    true
                }.onSuccess(result::success)
                    .onFailure { result.error("FOREGROUND_TASK", it.message, null) }
                "stopForegroundTask" -> {
                    NetworkTaskService.stop(this)
                    result.success(true)
                }
                "startLocalServerForeground" -> runCatching {
                    LocalServerTaskService.start(
                        this,
                        call.argument<String>("title") ?: "本地测试服务运行中",
                        call.argument<String>("detail") ?: "点击返回并停止服务",
                    )
                    true
                }.onSuccess(result::success)
                    .onFailure { result.error("LOCAL_SERVER_FOREGROUND", it.message, null) }
                "stopLocalServerForeground" -> {
                    LocalServerTaskService.stop(this)
                    result.success(true)
                }
                "saveStagedFile" -> startDocumentSave(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun startDocumentSave(call: MethodCall, result: MethodChannel.Result) {
        if (pendingDocumentSave != null) {
            result.error("SAVE_IN_PROGRESS", "Another Save As dialog is already open", null)
            return
        }
        val sourcePath = call.argument<String>("sourcePath").orEmpty()
        val source = runCatching { File(sourcePath).canonicalFile }.getOrNull()
        if (source == null || !source.isFile || !isPrivateStagingFile(source)) {
            result.error("INVALID_STAGING_FILE", "The download staging file is invalid", null)
            return
        }
        val fileName = call.argument<String>("fileName")?.trim().orEmpty()
        if (fileName.isEmpty()) {
            result.error("INVALID_FILE_NAME", "A destination file name is required", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = call.argument<String>("mimeType") ?: "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, fileName)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        pendingDocumentSave = PendingDocumentSave(source.path, result)
        runCatching { startActivityForResult(intent, REQUEST_CREATE_DOCUMENT) }
            .onFailure { error ->
                pendingDocumentSave = null
                result.error("SAVE_DIALOG", error.message, null)
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CREATE_DOCUMENT) return
        val pending = pendingDocumentSave ?: return
        pendingDocumentSave = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.result.success(null)
            return
        }
        executor.execute {
            runCatching {
                contentResolver.openOutputStream(uri, "w")?.use { output ->
                    FileInputStream(pending.sourcePath).use { input ->
                        input.copyTo(output, DEFAULT_BUFFER_SIZE)
                        output.flush()
                    }
                } ?: error("The selected document cannot be opened for writing")
                mapOf(
                    "uri" to uri.toString(),
                    "displayName" to documentDisplayName(uri),
                )
            }.onSuccess { value ->
                runOnUiThread { pending.result.success(value) }
            }.onFailure { error ->
                runOnUiThread {
                    pending.result.error("DOCUMENT_WRITE", error.message, null)
                }
            }
        }
    }

    private fun isPrivateStagingFile(file: File): Boolean {
        val candidate = file.canonicalPath
        return listOf(cacheDir, filesDir).any { root ->
            candidate.startsWith(root.canonicalPath + File.separator)
        }
    }

    private fun documentDisplayName(uri: Uri): String {
        return runCatching {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull().orEmpty().ifBlank { uri.lastPathSegment ?: "download" }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            runCatching(block).onSuccess { value ->
                runOnUiThread { result.success(value) }
            }.onFailure { error ->
                runOnUiThread { result.error("NATIVE_TASK", error.message, null) }
            }
        }
    }

    private fun getNetworkContext(): Map<String, Any?> {
        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connectivity.activeNetwork
            ?: return mapOf("connected" to false, "transports" to emptyList<String>())
        val capabilities = connectivity.getNetworkCapabilities(network)
        val link = connectivity.getLinkProperties(network)
        val transports = mutableListOf<String>()
        if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) transports += "wifi"
        if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true) transports += "cellular"
        if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true) transports += "ethernet"
        if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) transports += "vpn"

        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val wifiNetwork = if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) {
            network
        } else {
            connectivity.allNetworks.firstOrNull { candidate ->
                connectivity.getNetworkCapabilities(candidate)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            }
        }
        val wifiCapabilities = wifiNetwork?.let(connectivity::getNetworkCapabilities)
        val wifiLink = wifiNetwork?.let(connectivity::getLinkProperties)
        val cellularNetwork = if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true) {
            network
        } else {
            connectivity.allNetworks.firstOrNull { candidate ->
                connectivity.getNetworkCapabilities(candidate)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true
            }
        }
        var wifiInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            wifiCapabilities?.transportInfo as? WifiInfo
        } else {
            null
        }
        if (wifiNetwork != null &&
            (wifiInfo == null || wifiInfo.ssid == WifiManager.UNKNOWN_SSID)) {
            @Suppress("DEPRECATION")
            val legacyInfo = wifiManager.connectionInfo
            wifiInfo = legacyInfo
        }
        val addresses = link?.linkAddresses?.map { address ->
            mapOf(
                "address" to address.address.hostAddress?.substringBefore('%'),
                "prefixLength" to address.prefixLength,
                "family" to if (address.address is Inet4Address) "IPv4" else "IPv6",
            )
        } ?: emptyList()
        val gateways = link?.routes
            ?.filter { it.isDefaultRoute }
            ?.mapNotNull { it.gateway?.hostAddress?.substringBefore('%') }
            ?: emptyList()

        return mapOf(
            "connected" to true,
            "networkHandle" to network.networkHandle.toString(),
            "interfaceName" to link?.interfaceName,
            "transports" to transports,
            "validated" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            "captivePortal" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL) == true),
            // NET_CAPABILITY_PARTIAL_CONNECTIVITY is capability 24 on Android
            // 11+, but the symbol is hidden from some public SDK stubs.
            "partialConnectivity" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                capabilities?.hasCapability(24) == true),
            "metered" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true),
            "addresses" to addresses,
            "dnsServers" to (link?.dnsServers?.mapNotNull { it.hostAddress?.substringBefore('%') } ?: emptyList()),
            "gateways" to gateways,
            "lanAddresses" to (wifiLink?.linkAddresses?.map { address ->
                mapOf(
                    "address" to address.address.hostAddress?.substringBefore('%'),
                    "prefixLength" to address.prefixLength,
                    "family" to if (address.address is Inet4Address) "IPv4" else "IPv6",
                )
            } ?: addresses),
            "lanGateways" to (wifiLink?.routes
                ?.filter { it.isDefaultRoute }
                ?.mapNotNull { it.gateway?.hostAddress?.substringBefore('%') }
                ?: gateways),
            "mtu" to (link?.mtu ?: 0),
            "wifi" to wifiInfo?.let(::wifiInfoMap),
            "cellular" to cellularNetwork?.let { cellularInfoMap() },
        )
    }

    private fun requestWifiConnection(call: MethodCall): Map<String, Any?> {
        val ssid = call.argument<String>("ssid")?.trim().orEmpty()
        require(ssid.isNotEmpty()) { "SSID is required" }
        val password = call.argument<String>("password").orEmpty()
        val security = call.argument<String>("security").orEmpty().uppercase()
        val hidden = call.argument<Boolean>("hidden") ?: false
        require(!security.contains("EAP") && !security.contains("ENTERPRISE")) {
            "Enterprise Wi-Fi requires identity and certificate settings; use Android system Wi-Fi settings"
        }
        require(!security.contains("WEP")) { "WEP profiles are not supported" }
        val enhancedOpen = security.contains("OWE")
        val open = security.isBlank() ||
            security.contains("OPEN") ||
            security.contains("NONE") ||
            security == "--" ||
            enhancedOpen
        if (!open) require(password.length >= 8) { "Wi-Fi password must contain at least 8 characters" }

        val builder = WifiNetworkSuggestion.Builder()
            .setSsid(ssid)
            .setIsHiddenSsid(hidden)
        when {
            enhancedOpen -> builder.setIsEnhancedOpen(true)
            open -> Unit
            security.contains("WPA3") && !security.contains("WPA2") ->
                builder.setWpa3Passphrase(password)
            else -> builder.setWpa2Passphrase(password)
        }
        val suggestion = builder.build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(Settings.ACTION_WIFI_ADD_NETWORKS).apply {
                putParcelableArrayListExtra(
                    Settings.EXTRA_WIFI_NETWORK_LIST,
                    arrayListOf(suggestion),
                )
            }
            startActivity(intent)
            return mapOf(
                "status" to "user_confirmation_required",
                "systemUiOpened" to true,
                "message" to "Review and approve the Wi-Fi network in Android system UI",
            )
        }
        val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val status = manager.addNetworkSuggestions(listOf(suggestion))
        check(status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS ||
            status == WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_DUPLICATE) {
            "Android rejected the Wi-Fi suggestion (status=$status)"
        }
        return mapOf(
            "status" to "suggestion_registered",
            "systemUiOpened" to false,
            "message" to "Wi-Fi suggestion registered; Android controls the final connection",
        )
    }

    private fun runWifiRtt(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error("WIFI_RTT_UNSUPPORTED", "Wi-Fi RTT requires Android 9 or later", null)
            return
        }
        val bssid = call.argument<String>("bssid")?.trim().orEmpty()
        val accessPoint = lastWifiScanResults.firstOrNull {
            it.BSSID.equals(bssid, ignoreCase = true)
        }
        if (accessPoint == null) {
            result.error("WIFI_RTT_STALE_SCAN", "Run a fresh Wi-Fi scan before ranging", null)
            return
        }
        if (!accessPoint.is80211mcResponder) {
            result.error("WIFI_RTT_NOT_RESPONDER", "The access point does not advertise FTM responder capability", null)
            return
        }
        val manager = getSystemService(Context.WIFI_RTT_RANGING_SERVICE) as? WifiRttManager
        if (manager == null || !manager.isAvailable) {
            result.error("WIFI_RTT_UNAVAILABLE", "Wi-Fi RTT is currently unavailable", null)
            return
        }
        val request = RangingRequest.Builder().addAccessPoint(accessPoint).build()
        try {
            manager.startRanging(request, mainExecutor, object : RangingResultCallback() {
                override fun onRangingFailure(code: Int) {
                    result.error("WIFI_RTT_FAILED", "Wi-Fi RTT ranging failed (code=$code)", null)
                }

                override fun onRangingResults(results: MutableList<RangingResult>) {
                    val row = results.firstOrNull { it.macAddress.toString().equals(bssid, true) }
                        ?: results.firstOrNull()
                    if (row == null || row.status != RangingResult.STATUS_SUCCESS) {
                        result.error(
                            "WIFI_RTT_NO_RESULT",
                            "The access point returned no successful ranging result",
                            null,
                        )
                        return
                    }
                    result.success(
                        mapOf(
                            "bssid" to row.macAddress.toString(),
                            "distanceMm" to row.distanceMm,
                            "distanceStdDevMm" to row.distanceStdDevMm,
                            "rssi" to row.rssi,
                            "attemptedMeasurements" to row.numAttemptedMeasurements,
                            "successfulMeasurements" to row.numSuccessfulMeasurements,
                            "timestampMillis" to System.currentTimeMillis(),
                        ),
                    )
                }
            })
        } catch (error: SecurityException) {
            result.error("WIFI_RTT_PERMISSION", error.message, null)
        } catch (error: IllegalArgumentException) {
            result.error("WIFI_RTT_REQUEST", error.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun cellularInfoMap(): Map<String, Any?> {
        val telephony = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val cells = try {
            telephony.allCellInfo.orEmpty()
        } catch (_: SecurityException) {
            emptyList()
        } catch (_: UnsupportedOperationException) {
            emptyList()
        }
        val serving = cells.firstOrNull { it.isRegistered } ?: cells.firstOrNull()
        val radio = serving?.let(::cellRadioMap) ?: emptyMap()
        return mapOf(
            "operatorName" to telephony.networkOperatorName.takeIf { it.isNotBlank() },
            "operatorCode" to telephony.networkOperator.takeIf { it.isNotBlank() },
            "simOperatorName" to telephony.simOperatorName.takeIf { it.isNotBlank() },
            "simOperatorCode" to telephony.simOperator.takeIf { it.isNotBlank() },
            "roaming" to telephony.isNetworkRoaming,
            "registered" to (serving?.isRegistered ?: false),
            "radioTechnology" to radio["radioTechnology"],
            "dbm" to radio["dbm"],
            "level" to radio["level"],
            "metrics" to (radio["metrics"] ?: emptyMap<String, Int>()),
            "identity" to (radio["identity"] ?: emptyMap<String, Any?>()),
            "neighborCellCount" to cells.count { !it.isRegistered },
        )
    }

    private fun cellRadioMap(cell: CellInfo): Map<String, Any?> = when (cell) {
        is CellInfoLte -> {
            val signal = cell.cellSignalStrength
            val identity: CellIdentityLte = cell.cellIdentity
            mapOf(
                "radioTechnology" to "LTE",
                "dbm" to available(signal.dbm),
                "level" to signal.level,
                "metrics" to mapOf(
                    "RSRP" to available(signal.rsrp),
                    "RSRQ" to available(signal.rsrq),
                    "RSSNR" to available(signal.rssnr),
                    "RSSI" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) available(signal.rssi) else null,
                    "CQI" to available(signal.cqi),
                    "Timing Advance" to available(signal.timingAdvance),
                ).filterValues { it != null },
                "identity" to mapOf(
                    "CI" to available(identity.ci),
                    "PCI" to available(identity.pci),
                    "TAC" to available(identity.tac),
                    "EARFCN" to available(identity.earfcn),
                    "Bandwidth kHz" to available(identity.bandwidth),
                    "Bands" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) identity.bands.joinToString(", ") else null,
                    "MCC" to identity.mccString,
                    "MNC" to identity.mncString,
                ).filterValues { it != null },
            )
        }
        is CellInfoNr -> {
            val signal = cell.cellSignalStrength as CellSignalStrengthNr
            val identity: CellIdentityNr = cell.cellIdentity as CellIdentityNr
            mapOf(
                "radioTechnology" to "5G NR",
                "dbm" to available(signal.dbm),
                "level" to signal.level,
                "metrics" to mapOf(
                    "SS-RSRP" to available(signal.ssRsrp),
                    "SS-RSRQ" to available(signal.ssRsrq),
                    "SS-SINR" to available(signal.ssSinr),
                    "CSI-RSRP" to available(signal.csiRsrp),
                    "CSI-RSRQ" to available(signal.csiRsrq),
                    "CSI-SINR" to available(signal.csiSinr),
                ).filterValues { it != null },
                "identity" to mapOf(
                    "NCI" to available(identity.nci),
                    "PCI" to available(identity.pci),
                    "TAC" to available(identity.tac),
                    "NRARFCN" to available(identity.nrarfcn),
                    "Bands" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) identity.bands.joinToString(", ") else null,
                    "MCC" to identity.mccString,
                    "MNC" to identity.mncString,
                ).filterValues { it != null },
            )
        }
        is CellInfoWcdma -> mapOf(
            "radioTechnology" to "WCDMA",
            "dbm" to available(cell.cellSignalStrength.dbm),
            "level" to cell.cellSignalStrength.level,
            "metrics" to mapOf(
                "Ec/No" to available(cell.cellSignalStrength.getEcNo()),
            ).filterValues { it != null },
            "identity" to mapOf(
                "CID" to available(cell.cellIdentity.cid),
                "LAC" to available(cell.cellIdentity.lac),
                "PSC" to available(cell.cellIdentity.psc),
                "UARFCN" to available(cell.cellIdentity.uarfcn),
            ).filterValues { it != null },
        )
        is CellInfoGsm -> mapOf(
            "radioTechnology" to "GSM",
            "dbm" to available(cell.cellSignalStrength.dbm),
            "level" to cell.cellSignalStrength.level,
            "metrics" to mapOf(
                "RSSI" to available(cell.cellSignalStrength.dbm),
                "BER" to available(cell.cellSignalStrength.bitErrorRate),
                "Timing Advance" to available(cell.cellSignalStrength.timingAdvance),
            ).filterValues { it != null },
            "identity" to mapOf(
                "CID" to available(cell.cellIdentity.cid),
                "LAC" to available(cell.cellIdentity.lac),
                "ARFCN" to available(cell.cellIdentity.arfcn),
                "BSIC" to available(cell.cellIdentity.bsic),
            ).filterValues { it != null },
        )
        is CellInfoTdscdma -> mapOf(
            "radioTechnology" to "TD-SCDMA",
            "dbm" to available(cell.cellSignalStrength.dbm),
            "level" to cell.cellSignalStrength.level,
            "metrics" to mapOf(
                "RSCP" to available((cell.cellSignalStrength as CellSignalStrengthTdscdma).getRscp()),
            ).filterValues { it != null },
            "identity" to mapOf(
                "CID" to available(cell.cellIdentity.cid),
                "LAC" to available(cell.cellIdentity.lac),
                "UARFCN" to available(cell.cellIdentity.uarfcn),
            ).filterValues { it != null },
        )
        is CellInfoCdma -> mapOf(
            "radioTechnology" to "CDMA/EVDO",
            "dbm" to available(cell.cellSignalStrength.dbm),
            "level" to cell.cellSignalStrength.level,
            "metrics" to mapOf(
                "CDMA dBm" to available(cell.cellSignalStrength.cdmaDbm),
                "CDMA Ec/Io" to available(cell.cellSignalStrength.cdmaEcio),
                "EVDO dBm" to available(cell.cellSignalStrength.evdoDbm),
                "EVDO SNR" to available(cell.cellSignalStrength.evdoSnr),
            ).filterValues { it != null },
            "identity" to mapOf(
                "Base Station ID" to available(cell.cellIdentity.basestationId),
                "Network ID" to available(cell.cellIdentity.networkId),
                "System ID" to available(cell.cellIdentity.systemId),
            ).filterValues { it != null },
        )
        else -> emptyMap()
    }

    private fun available(value: Int): Int? = value.takeUnless { it == CellInfo.UNAVAILABLE || it == Int.MAX_VALUE }
    private fun available(value: Long): Long? = value.takeUnless { it == CellInfo.UNAVAILABLE.toLong() || it == Long.MAX_VALUE }

    private fun wifiInfoMap(info: WifiInfo): Map<String, Any?> = mapOf(
        "ssid" to info.ssid?.removeSurrounding("\""),
        "bssid" to info.bssid,
        "rssi" to info.rssi,
        "signalLevel" to WifiManager.calculateSignalLevel(info.rssi, 5),
        "frequency" to info.frequency,
        "channel" to frequencyToChannel(info.frequency),
        "linkSpeedMbps" to info.linkSpeed,
        "rxLinkSpeedMbps" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) info.rxLinkSpeedMbps else null,
        "txLinkSpeedMbps" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) info.txLinkSpeedMbps else null,
        "standard" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) wifiStandardName(info.wifiStandard) else null,
        "securityType" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) securityTypeName(info.currentSecurityType) else null,
        "apMldMacAddress" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) info.apMldMacAddress?.toString() else null,
        "associatedMloLinkCount" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) info.associatedMloLinks.size else null,
    )

    @Suppress("DEPRECATION")
    private fun scanWifi(result: MethodChannel.Result) {
        val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val completed = AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())
        lateinit var receiver: BroadcastReceiver

        fun complete(fresh: Boolean, requested: Boolean, status: String) {
            if (!completed.compareAndSet(false, true)) return
            runCatching { applicationContext.unregisterReceiver(receiver) }
            runCatching { wifiScanSnapshot(manager, fresh, requested, status) }
                .onSuccess(result::success)
                .onFailure { result.error("WIFI_SCAN", it.message, null) }
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val updated = intent?.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false) == true
                complete(
                    fresh = updated,
                    requested = true,
                    status = if (updated) "fresh" else "system_cached",
                )
            }
        }

        try {
            val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                applicationContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                applicationContext.registerReceiver(receiver, filter)
            }
            val requested = manager.startScan()
            if (!requested) {
                complete(false, false, "throttled_or_cached")
                return
            }
            handler.postDelayed(
                { complete(false, true, "timeout_cached") },
                8_000,
            )
        } catch (error: Throwable) {
            if (completed.compareAndSet(false, true)) {
                runCatching { applicationContext.unregisterReceiver(receiver) }
                result.error("WIFI_SCAN", error.message, null)
            }
        }
    }

    private fun wifiScanSnapshot(
        manager: WifiManager,
        fresh: Boolean,
        requested: Boolean,
        status: String,
    ): Map<String, Any?> {
        val nowMicros = SystemClock.elapsedRealtimeNanos() / 1_000
        val scanResults = manager.scanResults.sortedByDescending(ScanResult::level)
        lastWifiScanResults = scanResults
        val rows = scanResults.map { result ->
                val beacon = beaconCapabilities(result)
                mapOf(
                    "ssid" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        result.wifiSsid?.toString().orEmpty()
                    } else {
                        result.SSID
                    },
                    "bssid" to result.BSSID,
                    "rssi" to result.level,
                    "signalLevel" to WifiManager.calculateSignalLevel(result.level, 5),
                    "frequency" to result.frequency,
                    "channel" to frequencyToChannel(result.frequency),
                    "channelWidth" to channelWidthName(result.channelWidth),
                    "security" to result.capabilities,
                    "timestampMicros" to result.timestamp,
                    "ageMillis" to ((nowMicros - result.timestamp).coerceAtLeast(0) / 1_000),
                    "standard" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) wifiStandardName(result.wifiStandard) else null,
                    "centerFrequency0" to result.centerFreq0.takeIf { it > 0 },
                    "centerFrequency1" to result.centerFreq1.takeIf { it > 0 },
                    "securityTypes" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) result.securityTypes.map(::securityTypeName) else emptyList<String>(),
                    "passpoint" to result.isPasspointNetwork,
                    "rttResponder" to result.is80211mcResponder,
                    "stationCount" to beacon["stationCount"],
                    "channelUtilizationPercent" to beacon["channelUtilizationPercent"],
                    "dtimPeriod" to beacon["dtimPeriod"],
                    "supports80211k" to beacon["supports80211k"],
                    "supports80211v" to beacon["supports80211v"],
                    "supports80211r" to beacon["supports80211r"],
                    "pmfCapable" to beacon["pmfCapable"],
                    "pmfRequired" to beacon["pmfRequired"],
                    "informationElementIds" to beacon["informationElementIds"],
                )
            }
        val newestAgeMillis = rows.mapNotNull { it["ageMillis"] as? Long }.minOrNull()
        val usableChannels = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // WifiScanner itself is hidden from the public SDK, while
            // WifiManager#getUsableChannels requires its documented bitmask
            // values. Query every public Wi-Fi band independently so the
            // system regulatory domain remains the source of truth.
            listOf(1, 2, 4, 8).flatMap { band ->
                runCatching {
                    manager.getUsableChannels(
                        band,
                        WifiAvailableChannel.OP_MODE_STA,
                    )
                }.getOrDefault(emptyList())
            }.distinctBy { it.frequencyMhz }.map { channel ->
                mapOf(
                    "frequency" to channel.frequencyMhz,
                    "channel" to frequencyToChannel(channel.frequencyMhz),
                    "maximumWidthMhz" to channelWidthMhz(channel.channelWidth),
                )
            }
        } else {
            emptyList()
        }
        return mapOf(
            "accessPoints" to rows,
            "fresh" to fresh,
            "requested" to requested,
            "status" to status,
            "collectedAtMillis" to System.currentTimeMillis(),
            "newestResultAgeMillis" to newestAgeMillis,
            "supports24Ghz" to manager.is24GHzBandSupported,
            "supports5Ghz" to manager.is5GHzBandSupported,
            "supports6Ghz" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) manager.is6GHzBandSupported else false,
            "supportsRtt" to packageManager.hasSystemFeature("android.hardware.wifi.rtt"),
            "supportsEasyConnect" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) manager.isEasyConnectSupported else false,
            "supportsLocalOnlyHotspot" to true,
            "usableChannels" to usableChannels,
        )
    }

    private fun runPing(call: MethodCall): Map<String, Any?> {
        val host = validatedHost(call.argument<String>("host"))
        val count = (call.argument<Int>("count") ?: 4).coerceIn(1, 100)
        val timeoutMs = (call.argument<Int>("timeoutMs") ?: 2000).coerceIn(100, 30000)
        val intervalMs = (call.argument<Int>("intervalMs") ?: 1000).coerceIn(100, 10000)
        val packetSize = (call.argument<Int>("packetSize") ?: 56).coerceIn(0, 65000)
        val ipv6 = call.argument<Boolean>("ipv6") ?: host.contains(':')
        val binary = if (ipv6 && FileBinary.exists("/system/bin/ping6")) "/system/bin/ping6" else "/system/bin/ping"
        val args = mutableListOf(
            binary,
            "-c", count.toString(),
            "-W", max(1, timeoutMs / 1000).toString(),
            "-i", String.format(java.util.Locale.US, "%.1f", intervalMs / 1000.0),
            "-s", packetSize.toString(),
        )
        if (ipv6 && binary.endsWith("/ping")) args += "-6"
        args += host
        val process = ProcessBuilder(args).redirectErrorStream(true).start()
        val output = process.inputStream.bufferedReader().readText()
        val exitCode = process.waitFor()
        return mapOf("exitCode" to exitCode, "output" to output, "command" to args.joinToString(" "))
    }

    private fun runTraceroute(call: MethodCall): List<Map<String, Any?>> {
        val host = validatedHost(call.argument<String>("host"))
        val maxHops = (call.argument<Int>("maxHops") ?: 30).coerceIn(1, 64)
        val timeoutSeconds = max(1, (call.argument<Int>("timeoutMs") ?: 1800) / 1000)
        val probes = (call.argument<Int>("probes") ?: 3).coerceIn(1, 5)
        val resolveHostnames = call.argument<Boolean>("resolveHostnames") ?: true
        val resolvedTarget = runCatching { java.net.InetAddress.getAllByName(host).firstOrNull() }.getOrNull()
        val ipv6 = resolvedTarget is java.net.Inet6Address || host.contains(':')
        val pingBinary = if (ipv6 && FileBinary.exists("/system/bin/ping6")) {
            "/system/bin/ping6"
        } else {
            "/system/bin/ping"
        }
        val hops = mutableListOf<Map<String, Any?>>()
        tracerouteCancelled = false
        for (ttl in 1..maxHops) {
            if (tracerouteCancelled) break
            val samples = mutableListOf<Double?>()
            val rawOutputs = mutableListOf<String>()
            var address: String? = null
            var reached = false
            repeat(probes) {
                if (tracerouteCancelled) return@repeat
                val started = System.nanoTime()
                val args = mutableListOf(
                    pingBinary, "-c", "1", "-W", timeoutSeconds.toString(),
                    "-t", ttl.toString(),
                )
                if (ipv6 && pingBinary.endsWith("/ping")) args += "-6"
                args += host
                val process = ProcessBuilder(args).redirectErrorStream(true).start()
                activeTracerouteProcess = process
                val output = process.inputStream.bufferedReader().readText()
                val exitCode = runCatching { process.waitFor() }.getOrDefault(-1)
                activeTracerouteProcess = null
                val elapsed = (System.nanoTime() - started) / 1_000_000.0
                rawOutputs += output.trim()
                val addressPattern = Regex(
                    "((?:[0-9]{1,3}\\.){3}[0-9]{1,3}|(?:[0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f:%]+)",
                )
                val addresses = addressPattern.findAll(output).mapNotNull { match ->
                    val raw = match.groupValues[1]
                    sequenceOf(raw, raw.removeSuffix(":"))
                        .mapNotNull { candidate ->
                            runCatching { java.net.InetAddress.getByName(candidate).hostAddress }.getOrNull()
                        }
                        .firstOrNull()
                }.toList()
                address = addresses.lastOrNull() ?: address
                val probeReached = exitCode == 0 || output.contains("bytes from", ignoreCase = true)
                reached = reached || probeReached
                samples += if (addresses.isNotEmpty() || probeReached) elapsed else null
            }
            val validSamples = samples.filterNotNull()
            val elapsed = if (validSamples.isEmpty()) 0.0 else validSamples.average()
            val hostname = if (resolveHostnames && address != null) runCatching {
                java.net.InetAddress.getByName(address).canonicalHostName.takeUnless { it == address }
            }.getOrNull() else null
            hops += mapOf(
                "hop" to ttl,
                "address" to address,
                "hostname" to hostname,
                "elapsedMs" to elapsed,
                "samplesMs" to samples,
                "reached" to reached,
                "timeout" to validSamples.isEmpty(),
                "raw" to rawOutputs.joinToString("\n---\n"),
            )
            if (reached) break
        }
        activeTracerouteProcess = null
        return hops
    }

    private fun probePathMtu(call: MethodCall): Map<String, Any?> {
        val host = validatedHost(call.argument<String>("host"))
        val ipv6 = call.argument<Boolean>("ipv6") ?: host.contains(':')
        val interfaceMtu = (call.argument<Int>("interfaceMtu") ?: 1500).coerceIn(576, 65_535)
        val timeoutSeconds = (call.argument<Int>("timeoutMs") ?: 1600)
            .coerceIn(500, 10_000).let { max(1, it / 1000) }
        val overhead = if (ipv6) 48 else 28
        var low = if (ipv6) 1280 else 576
        var high = interfaceMtu
        var best: Int? = null
        val attempts = mutableListOf<Map<String, Any?>>()

        while (low <= high) {
            val mtu = (low + high) / 2
            val payload = (mtu - overhead).coerceAtLeast(0)
            val args = mutableListOf("/system/bin/ping", "-c", "1", "-W", timeoutSeconds.toString())
            if (ipv6) args += "-6"
            args += listOf("-M", "do", "-s", payload.toString(), host)
            val started = System.nanoTime()
            val process = ProcessBuilder(args).redirectErrorStream(true).start()
            val output = process.inputStream.bufferedReader().readText()
            val exitCode = process.waitFor()
            val elapsedMs = (System.nanoTime() - started) / 1_000_000.0
            if (output.contains("invalid option", ignoreCase = true) ||
                output.contains("unknown option", ignoreCase = true) ||
                output.contains("bad option", ignoreCase = true)) {
                throw UnsupportedOperationException("当前 Android ping 不支持禁止分片（-M do），无法可靠探测路径 MTU")
            }
            val success = exitCode == 0 && output.contains("bytes from", ignoreCase = true)
            attempts += mapOf(
                "mtu" to mtu,
                "payload" to payload,
                "success" to success,
                "elapsedMs" to elapsedMs,
                "output" to output.trim().take(500),
            )
            if (success) {
                best = mtu
                low = mtu + 1
            } else {
                high = mtu - 1
            }
        }
        return mapOf(
            "host" to host,
            "ipv6" to ipv6,
            "interfaceMtu" to interfaceMtu,
            "pathMtu" to best,
            "attempts" to attempts,
            "conclusive" to (best != null),
        )
    }

    private fun validatedHost(input: String?): String {
        val host = input?.trim().orEmpty()
        require(host.isNotEmpty() && host.length <= 253) { "目标地址为空或过长" }
        require(host.matches(Regex("^[0-9A-Za-z:.%-]+$"))) { "目标地址包含非法字符" }
        return host
    }

    private fun frequencyToChannel(frequency: Int): Int = when {
        frequency == 2484 -> 14
        frequency in 2412..2472 -> (frequency - 2407) / 5
        frequency in 5000..5895 -> (frequency - 5000) / 5
        frequency in 5955..7115 -> (frequency - 5950) / 5
        else -> 0
    }

    private fun channelWidthName(width: Int): String = when (width) {
        ScanResult.CHANNEL_WIDTH_20MHZ -> "20 MHz"
        ScanResult.CHANNEL_WIDTH_40MHZ -> "40 MHz"
        ScanResult.CHANNEL_WIDTH_80MHZ -> "80 MHz"
        ScanResult.CHANNEL_WIDTH_160MHZ -> "160 MHz"
        ScanResult.CHANNEL_WIDTH_80MHZ_PLUS_MHZ -> "80+80 MHz"
        ScanResult.CHANNEL_WIDTH_320MHZ -> "320 MHz"
        else -> "未知"
    }

    private fun channelWidthMhz(width: Int): Int = when (width) {
        ScanResult.CHANNEL_WIDTH_20MHZ -> 20
        ScanResult.CHANNEL_WIDTH_40MHZ -> 40
        ScanResult.CHANNEL_WIDTH_80MHZ -> 80
        ScanResult.CHANNEL_WIDTH_160MHZ -> 160
        ScanResult.CHANNEL_WIDTH_80MHZ_PLUS_MHZ -> 160
        ScanResult.CHANNEL_WIDTH_320MHZ -> 320
        else -> 20
    }

    private fun wifiStandardName(standard: Int): String = when (standard) {
        ScanResult.WIFI_STANDARD_LEGACY -> "Legacy"
        ScanResult.WIFI_STANDARD_11N -> "Wi-Fi 4 (802.11n)"
        ScanResult.WIFI_STANDARD_11AC -> "Wi-Fi 5 (802.11ac)"
        ScanResult.WIFI_STANDARD_11AX -> "Wi-Fi 6 (802.11ax)"
        ScanResult.WIFI_STANDARD_11AD -> "WiGig (802.11ad)"
        ScanResult.WIFI_STANDARD_11BE -> "Wi-Fi 7 (802.11be)"
        else -> "未知"
    }

    private fun securityTypeName(type: Int): String = when (type) {
        WifiInfo.SECURITY_TYPE_OPEN -> "Open"
        WifiInfo.SECURITY_TYPE_WEP -> "WEP"
        WifiInfo.SECURITY_TYPE_PSK -> "WPA2-Personal"
        WifiInfo.SECURITY_TYPE_EAP -> "WPA2-Enterprise"
        WifiInfo.SECURITY_TYPE_SAE -> "WPA3-Personal"
        WifiInfo.SECURITY_TYPE_OWE -> "OWE"
        WifiInfo.SECURITY_TYPE_EAP_WPA3_ENTERPRISE -> "WPA3-Enterprise"
        WifiInfo.SECURITY_TYPE_EAP_WPA3_ENTERPRISE_192_BIT -> "WPA3-Enterprise-192"
        WifiInfo.SECURITY_TYPE_PASSPOINT_R1_R2 -> "Passpoint R1/R2"
        WifiInfo.SECURITY_TYPE_PASSPOINT_R3 -> "Passpoint R3"
        WifiInfo.SECURITY_TYPE_DPP -> "DPP"
        else -> "Unknown"
    }

    private fun beaconCapabilities(result: ScanResult): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyMap()
        val elements = runCatching { result.informationElements }.getOrNull() ?: return emptyMap()
        val ids = elements.map { it.id }.distinct().sorted()
        var stationCount: Int? = null
        var utilization: Int? = null
        var dtim: Int? = null
        var supportsK: Boolean? = null
        var supportsV: Boolean? = null
        var supportsR: Boolean? = null
        var pmfCapable: Boolean? = null
        var pmfRequired: Boolean? = null
        for (element in elements) {
            val bytes = runCatching {
                val buffer = element.bytes.duplicate()
                ByteArray(buffer.remaining()).also(buffer::get)
            }.getOrNull() ?: continue
            when (element.id) {
                5 -> if (bytes.size >= 2) dtim = bytes[1].toInt() and 0xff
                11 -> if (bytes.size >= 3) {
                    stationCount = littleUnsignedShort(bytes, 0)
                    utilization = (((bytes[2].toInt() and 0xff) / 255.0) * 100).toInt()
                }
                48 -> parseRsnProtection(bytes)?.let {
                    pmfRequired = it.first
                    pmfCapable = it.second
                }
                54 -> supportsR = true
                70 -> supportsK = true
                127 -> if (bytes.size >= 3) {
                    supportsV = (bytes[2].toInt() and (1 shl 3)) != 0
                }
            }
        }
        if (supportsK == null) supportsK = false
        if (supportsV == null) supportsV = false
        if (supportsR == null) supportsR = false
        return mapOf(
            "stationCount" to stationCount,
            "channelUtilizationPercent" to utilization,
            "dtimPeriod" to dtim,
            "supports80211k" to supportsK,
            "supports80211v" to supportsV,
            "supports80211r" to supportsR,
            "pmfCapable" to pmfCapable,
            "pmfRequired" to pmfRequired,
            "informationElementIds" to ids,
        )
    }

    private fun littleUnsignedShort(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xff) or ((bytes[offset + 1].toInt() and 0xff) shl 8)

    private fun parseRsnProtection(bytes: ByteArray): Pair<Boolean, Boolean>? {
        if (bytes.size < 8) return null
        var offset = 2 + 4
        if (offset + 2 > bytes.size) return null
        val pairwiseCount = littleUnsignedShort(bytes, offset)
        offset += 2 + pairwiseCount * 4
        if (offset + 2 > bytes.size) return null
        val akmCount = littleUnsignedShort(bytes, offset)
        offset += 2 + akmCount * 4
        if (offset + 2 > bytes.size) return null
        val capabilities = littleUnsignedShort(bytes, offset)
        val required = capabilities and (1 shl 6) != 0
        val capable = capabilities and (1 shl 7) != 0
        return required to capable
    }

    override fun onDestroy() {
        networkEventMonitor.stop()
        bluetoothDebug.dispose()
        runCatching { multicastLock?.takeIf { it.isHeld }?.release() }
        multicastLock = null
        executor.shutdownNow()
        super.onDestroy()
    }
}

private object FileBinary {
    fun exists(path: String): Boolean = java.io.File(path).canExecute()
}
