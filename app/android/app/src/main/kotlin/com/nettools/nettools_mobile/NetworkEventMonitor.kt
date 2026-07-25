package com.nettools.nettools_mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

class NetworkEventMonitor(context: Context) : EventChannel.StreamHandler {
    private val connectivity = context.applicationContext
        .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var registered = false
    private var sequence = 0L

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = emit("available", network)
        override fun onLost(network: Network) = emit("lost", network)
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
            emit("capabilities", network, capabilities = capabilities)
        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) =
            emit("link", network, linkProperties = linkProperties)
        override fun onLosing(network: Network, maxMsToLive: Int) =
            emit("losing", network, extra = mapOf("maxMsToLive" to maxMsToLive))
        override fun onUnavailable() = emit("unavailable", null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        if (!registered) {
            connectivity.registerDefaultNetworkCallback(callback)
            registered = true
        }
        emit("snapshot", connectivity.activeNetwork)
    }

    override fun onCancel(arguments: Any?) {
        stop()
    }

    fun stop() {
        if (registered) runCatching { connectivity.unregisterNetworkCallback(callback) }
        registered = false
        sink = null
    }

    private fun emit(
        type: String,
        network: Network?,
        capabilities: NetworkCapabilities? = null,
        linkProperties: LinkProperties? = null,
        extra: Map<String, Any?> = emptyMap(),
    ) {
        val active = connectivity.activeNetwork
        val caps = capabilities ?: network?.let(connectivity::getNetworkCapabilities)
        val link = linkProperties ?: network?.let(connectivity::getLinkProperties)
        val transports = mutableListOf<String>()
        if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) transports += "wifi"
        if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true) transports += "cellular"
        if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true) transports += "ethernet"
        if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) transports += "vpn"
        val wifi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            caps?.transportInfo as? WifiInfo
        } else null
        val addresses = link?.linkAddresses?.map {
            mapOf(
                "address" to it.address.hostAddress?.substringBefore('%'),
                "prefixLength" to it.prefixLength,
            )
        } ?: emptyList()
        val routes = link?.routes?.map {
            mapOf(
                "destination" to it.destination.toString(),
                "gateway" to it.gateway?.hostAddress?.substringBefore('%'),
                "default" to it.isDefaultRoute,
            )
        } ?: emptyList()
        val payload = mutableMapOf<String, Any?>(
            "sequence" to ++sequence,
            "timestampMs" to System.currentTimeMillis(),
            "type" to type,
            "networkHandle" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) network?.networkHandle else null,
            "isDefault" to (network != null && network == active),
            "connected" to (active != null),
            "transports" to transports,
            "validated" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            "captivePortal" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL) == true),
            // Capability 24 is PARTIAL_CONNECTIVITY on Android 11+, but the
            // constant is hidden from some public SDK stubs.
            "partialConnectivity" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && caps?.hasCapability(24) == true),
            "metered" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true),
            "interfaceName" to link?.interfaceName,
            "mtu" to link?.mtu,
            "addresses" to addresses,
            "dnsServers" to (link?.dnsServers?.mapNotNull { it.hostAddress?.substringBefore('%') } ?: emptyList()),
            "routes" to routes,
            "ssid" to wifi?.ssid?.takeUnless { it == "<unknown ssid>" },
            "bssid" to wifi?.bssid?.takeUnless { it == "02:00:00:00:00:00" },
            "rssi" to wifi?.rssi,
            "frequency" to wifi?.frequency,
            "linkSpeedMbps" to wifi?.linkSpeed,
        )
        payload.putAll(extra)
        mainHandler.post { sink?.success(payload) }
    }
}
