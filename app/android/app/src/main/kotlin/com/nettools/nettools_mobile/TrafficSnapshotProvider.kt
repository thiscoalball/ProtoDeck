package com.nettools.nettools_mobile

import android.net.TrafficStats
import android.net.ConnectivityManager
import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Process
import java.io.File
import java.io.ByteArrayOutputStream
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap

object TrafficSnapshotProvider {
    private data class AppIdentity(val label: String, val icon: ByteArray?)
    private val identityCache = ConcurrentHashMap<String, AppIdentity>()

    fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        return appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        ) == AppOpsManager.MODE_ALLOWED
    }

    fun appTraffic(context: Context, sinceMs: Long): List<Map<String, Any?>> {
        if (!hasUsageAccess(context)) throw SecurityException("请先授予使用情况访问权限")
        val manager = context.getSystemService(Context.NETWORK_STATS_SERVICE) as NetworkStatsManager
        val totals = mutableMapOf<Int, LongArray>()
        val now = System.currentTimeMillis()
        listOf(ConnectivityManager.TYPE_WIFI, ConnectivityManager.TYPE_MOBILE).forEach { type ->
            runCatching { manager.querySummary(type, null, sinceMs.coerceAtMost(now), now) }
                .onSuccess { stats ->
                    stats.use {
                        val bucket = NetworkStats.Bucket()
                        while (stats.hasNextBucket()) {
                            stats.getNextBucket(bucket)
                            if (bucket.uid < 0) continue
                            val value = totals.getOrPut(bucket.uid) { longArrayOf(0, 0) }
                            value[0] += bucket.rxBytes
                            value[1] += bucket.txBytes
                        }
                    }
                }
        }
        val packages = context.packageManager
        return totals.entries
            .filter { it.value[0] > 0 || it.value[1] > 0 }
            .sortedByDescending { it.value[0] + it.value[1] }
            .take(200)
            .map { (uid, bytes) ->
                val packageNames = packages.getPackagesForUid(uid)
                    ?.distinct()
                    ?.sorted()
                    .orEmpty()
                val primaryInfo = packageNames.firstNotNullOfOrNull { name ->
                    runCatching { packages.getApplicationInfo(name, 0) }.getOrNull()
                }
                val packageName = primaryInfo?.packageName ?: packageNames.firstOrNull()
                val identity = primaryInfo?.let { info ->
                    identityCache.getOrPut(info.packageName) {
                        AppIdentity(
                            label = runCatching {
                                packages.getApplicationLabel(info).toString()
                            }.getOrDefault(info.packageName),
                            icon = runCatching { drawablePng(packages.getApplicationIcon(info)) }.getOrNull(),
                        )
                    }
                }
                val systemName = packages.getNameForUid(uid)
                mapOf(
                    "uid" to uid,
                    "packageName" to packageName,
                    "packageNames" to packageNames,
                    "label" to (identity?.label ?: packageName ?: systemName ?: "UID $uid"),
                    "iconBytes" to identity?.icon,
                    "rxBytes" to bytes[0],
                    "txBytes" to bytes[1],
                )
            }
    }

    fun snapshot(): Map<String, Any?> {
        val connections = mutableListOf<Map<String, Any?>>()
        val errors = mutableListOf<String>()
        listOf(
            Triple("TCP", "/proc/net/tcp", false),
            Triple("TCP", "/proc/net/tcp6", true),
            Triple("UDP", "/proc/net/udp", false),
            Triple("UDP", "/proc/net/udp6", true),
        ).forEach { (protocol, path, ipv6) ->
            runCatching { parseSocketTable(File(path), protocol, ipv6) }
                .onSuccess(connections::addAll)
                .onFailure { errors += "$path: ${it.message ?: "不可访问"}" }
        }
        val totalRx = TrafficStats.getTotalRxBytes().takeIf { it >= 0 }
        val totalTx = TrafficStats.getTotalTxBytes().takeIf { it >= 0 }
        return mapOf(
            "timestampMs" to System.currentTimeMillis(),
            "elapsedRealtimeMs" to android.os.SystemClock.elapsedRealtime(),
            "totalRxBytes" to totalRx,
            "totalTxBytes" to totalTx,
            "mobileRxBytes" to TrafficStats.getMobileRxBytes().takeIf { it >= 0 },
            "mobileTxBytes" to TrafficStats.getMobileTxBytes().takeIf { it >= 0 },
            "appRxBytes" to TrafficStats.getUidRxBytes(Process.myUid()).takeIf { it >= 0 },
            "appTxBytes" to TrafficStats.getUidTxBytes(Process.myUid()).takeIf { it >= 0 },
            "connections" to connections.take(2_000),
            "connectionVisibility" to if (errors.size == 4) "restricted" else "available",
            "visibilityDetail" to errors.joinToString("；").take(500),
        )
    }

    private fun parseSocketTable(
        file: File,
        protocol: String,
        ipv6: Boolean,
    ): List<Map<String, Any?>> {
        val rows = mutableListOf<Map<String, Any?>>()
        file.useLines { lines ->
            lines.drop(1).forEach { line ->
                val fields = line.trim().split(Regex("\\s+"))
                if (fields.size < 8) return@forEach
                val local = parseEndpoint(fields[1], ipv6) ?: return@forEach
                val remote = parseEndpoint(fields[2], ipv6) ?: return@forEach
                val stateCode = fields[3]
                if (remote.second == 0 || isUnspecified(remote.first)) return@forEach
                rows += mapOf(
                    "protocol" to protocol,
                    "ipVersion" to if (ipv6) 6 else 4,
                    "localAddress" to local.first,
                    "localPort" to local.second,
                    "remoteAddress" to remote.first,
                    "remotePort" to remote.second,
                    "state" to socketState(protocol, stateCode),
                    "uid" to fields.getOrNull(7)?.toIntOrNull(),
                    "applicationProtocol" to applicationProtocol(local.second, remote.second, protocol),
                )
            }
        }
        return rows
    }

    private fun parseEndpoint(value: String, ipv6: Boolean): Pair<String, Int>? {
        val pieces = value.split(':')
        if (pieces.size != 2) return null
        val raw = pieces[0]
        val port = pieces[1].toIntOrNull(16) ?: return null
        return if (!ipv6) {
            if (raw.length != 8) return null
            val bytes = ByteArray(4)
            for (index in 0 until 4) {
                bytes[index] = raw.substring((3 - index) * 2, (4 - index) * 2).toInt(16).toByte()
            }
            InetAddress.getByAddress(bytes).hostAddress.orEmpty() to port
        } else {
            if (raw.length != 32) return null
            val bytes = ByteArray(16)
            // Linux prints each 32-bit IPv6 word in host byte order in /proc/net/*6.
            for (word in 0 until 4) {
                for (byte in 0 until 4) {
                    val source = word * 8 + (3 - byte) * 2
                    bytes[word * 4 + byte] = raw.substring(source, source + 2).toInt(16).toByte()
                }
            }
            InetAddress.getByAddress(bytes).hostAddress.orEmpty().substringBefore('%') to port
        }
    }

    private fun isUnspecified(address: String): Boolean =
        address == "0.0.0.0" || address == "0:0:0:0:0:0:0:0" || address == "::"

    private fun socketState(protocol: String, code: String): String {
        if (protocol == "UDP") return "UNCONN"
        return when (code.uppercase()) {
            "01" -> "ESTABLISHED"
            "02" -> "SYN_SENT"
            "03" -> "SYN_RECV"
            "04" -> "FIN_WAIT1"
            "05" -> "FIN_WAIT2"
            "06" -> "TIME_WAIT"
            "07" -> "CLOSE"
            "08" -> "CLOSE_WAIT"
            "09" -> "LAST_ACK"
            "0A" -> "LISTEN"
            "0B" -> "CLOSING"
            else -> code
        }
    }

    private fun applicationProtocol(localPort: Int, remotePort: Int, transport: String): String {
        val ports = setOf(localPort, remotePort)
        return when {
            53 in ports -> "DNS"
            67 in ports || 68 in ports -> "DHCP"
            80 in ports || 8080 in ports -> "HTTP"
            443 in ports -> if (transport == "UDP") "QUIC" else "HTTPS"
            22 in ports -> "SSH"
            23 in ports -> "Telnet"
            123 in ports -> "NTP"
            161 in ports || 162 in ports -> "SNMP"
            514 in ports || 601 in ports || 6514 in ports -> "Syslog"
            1883 in ports || 8883 in ports -> "MQTT"
            445 in ports -> "SMB"
            else -> "Unknown"
        }
    }

    private fun drawablePng(drawable: Drawable): ByteArray {
        val width = drawable.intrinsicWidth.takeIf { it > 0 }?.coerceAtMost(96) ?: 64
        val height = drawable.intrinsicHeight.takeIf { it > 0 }?.coerceAtMost(96) ?: 64
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            bitmap.recycle()
            output.toByteArray()
        }
    }
}
