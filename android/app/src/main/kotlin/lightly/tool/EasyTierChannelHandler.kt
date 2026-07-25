package lightly.tool

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.easytier.jni.EasyTierJNI
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class EasyTierChannelHandler internal constructor(
    private val nativeRuntime: EasyTierNativeRuntime,
    private val vpnPlatform: EasyTierVpnPlatform,
    private val stateStore: EasyTierRuntimeStateStore,
    private val monitorScheduler: EasyTierMonitorScheduler,
) {
    constructor(activity: Activity) : this(
        nativeRuntime = JniEasyTierNativeRuntime,
        vpnPlatform = AndroidEasyTierVpnPlatform(activity),
        stateStore = AndroidEasyTierRuntimeStateStore,
        monitorScheduler = HandlerEasyTierMonitorScheduler(),
    )

    private var pendingVpnPermissionResult: MethodChannel.Result? = null
    private var pendingVpnConfig: String? = null
    private var pendingVpnInstanceName: String? = null
    private var runningInstanceName: String? = null
    private var currentIpv4: String? = null
    private var monitorTick = 0
    private var runningConfig: String? = null
    private var missingInfoTicks = 0
    private var notRunningTicks = 0
    private var restartInProgress = false
    private var useAndroidVpn = true

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(::handle)
    }

    internal fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_PARSE_CONFIG -> parseConfig(call, result)
            METHOD_START_VPN -> startVpn(call, result)
            METHOD_CHECK_VPN_PERMISSION -> {
                result.success(vpnPlatform.hasVpnPermission())
            }
            METHOD_STOP_VPN -> stopVpn(result)
            METHOD_GET_NETWORK_INFO -> getNetworkInfo(result)
            METHOD_GET_LAST_ERROR -> getLastError(result)
            else -> result.notImplemented()
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != VPN_PERMISSION_REQUEST_CODE) {
            return false
        }
        finishPendingVpnPermissionResult(resultCode == Activity.RESULT_OK)
        return true
    }

    fun shutdown() {
        runCatching {
            stopMonitor()
            vpnPlatform.stopVpnService(forceStop = false)
        }.onFailure { error ->
            Log.w(CHANNEL_NAME, "Failed to stop EasyTier VPN service", error)
        }
        runCatching {
            nativeRuntime.stopAllInstances()
            runningConfig = null
        }.onFailure { error ->
            Log.w(CHANNEL_NAME, "Failed to stop EasyTier instances", error)
        }
    }

    private fun parseConfig(call: MethodCall, result: MethodChannel.Result) {
        val config = call.argument<String>(ARG_CONFIG)
        if (config.isNullOrBlank()) {
            result.error(ERROR_INVALID_CONFIG, "Config is required", null)
            return
        }
        try {
            if (nativeRuntime.parseConfig(config) == 0) {
                result.success(true)
            } else {
                result.error(
                    ERROR_PARSE_FAILED,
                    nativeRuntime.getLastError() ?: "Config parse failed",
                    null,
                )
            }
        } catch (error: Exception) {
            result.error(ERROR_EXCEPTION, error.message, null)
        }
    }

    private fun startVpn(call: MethodCall, result: MethodChannel.Result) {
        val config = call.argument<String>(ARG_CONFIG)
        val instanceName = call.argument<String>(ARG_INSTANCE_NAME)
        val requestedAndroidVpn = call.argument<Boolean>(ARG_USE_ANDROID_VPN) ?: true
        if (config.isNullOrBlank() || instanceName.isNullOrBlank()) {
            result.error(
                ERROR_INVALID_CONFIG,
                "Config and instanceName are required",
                null,
            )
            return
        }

        if (!requestedAndroidVpn) {
            vpnPlatform.stopVpnService(forceStop = true)
            startVpnWithConfig(config, instanceName, result, useAndroidVpn = false)
            return
        }

        if (!vpnPlatform.hasVpnPermission()) {
            pendingVpnPermissionResult = result
            pendingVpnConfig = config
            pendingVpnInstanceName = instanceName
            vpnPlatform.requestVpnPermission(VPN_PERMISSION_REQUEST_CODE)
            return
        }
        startVpnWithConfig(config, instanceName, result, useAndroidVpn = true)
    }

    private fun finishPendingVpnPermissionResult(granted: Boolean) {
        val pendingResult = pendingVpnPermissionResult ?: return
        val config = pendingVpnConfig
        val instanceName = pendingVpnInstanceName
        pendingVpnPermissionResult = null
        pendingVpnConfig = null
        pendingVpnInstanceName = null

        if (granted && config != null && instanceName != null) {
            startVpnWithConfig(config, instanceName, pendingResult, useAndroidVpn = true)
        } else {
            pendingResult.error(
                ERROR_VPN_PERMISSION_DENIED,
                "User denied VPN permission",
                null,
            )
        }
    }

    private fun startVpnWithConfig(
        config: String,
        instanceName: String,
        result: MethodChannel.Result,
        useAndroidVpn: Boolean,
    ) {
        try {
            val nativeResult = nativeRuntime.runNetworkInstance(config)
            if (nativeResult == 0) {
                runningConfig = config
                startMonitor(instanceName)
                this.useAndroidVpn = useAndroidVpn
                stateStore.markStarted(instanceName)
                result.success(true)
            } else {
                result.error(
                    ERROR_START_FAILED,
                    nativeRuntime.getLastError() ?: "VPN start failed",
                    null,
                )
            }
        } catch (error: Exception) {
            result.error(ERROR_EXCEPTION, error.message, null)
        }
    }

    private fun stopVpn(result: MethodChannel.Result) {
        try {
            stopMonitor()
            vpnPlatform.stopVpnService(forceStop = true)
            nativeRuntime.stopAllInstances()
            stateStore.clear()
            runningConfig = null
            useAndroidVpn = true
            result.success(true)
        } catch (error: Exception) {
            result.error(ERROR_EXCEPTION, error.message, null)
        }
    }

    private fun getNetworkInfo(result: MethodChannel.Result) {
        try {
            val info = nativeRuntime.collectNetworkInfos()
            if (!info.isNullOrBlank()) {
                stateStore.refreshFromNative()
            }
            result.success(info)
        } catch (error: Exception) {
            result.error(ERROR_EXCEPTION, error.message, null)
        }
    }

    private fun getLastError(result: MethodChannel.Result) {
        try {
            result.success(nativeRuntime.getLastError())
        } catch (error: Exception) {
            result.error(ERROR_EXCEPTION, error.message, null)
        }
    }

    private fun startMonitor(instanceName: String) {
        stopMonitor()
        runningInstanceName = instanceName
        currentIpv4 = null
        monitorTick = 0
        missingInfoTicks = 0
        notRunningTicks = 0
        restartInProgress = false
        monitorScheduler.start(::monitorStatus)
    }

    private fun stopMonitor() {
        monitorScheduler.stop()
        runningInstanceName = null
        currentIpv4 = null
        monitorTick = 0
        missingInfoTicks = 0
        notRunningTicks = 0
        restartInProgress = false
        useAndroidVpn = true
        stateStore.clear()
    }

    private fun monitorStatus() {
        val instanceName = runningInstanceName ?: return
        monitorTick += 1
        val infosJson = nativeRuntime.collectNetworkInfos()
        if (infosJson.isNullOrBlank()) {
            missingInfoTicks += 1
            Log.d(LOG_TAG, "No network info returned yet count=$missingInfoTicks")
            if (missingInfoTicks >= 4) {
                restartInstance("missing-network-info")
            }
            return
        }
        missingInfoTicks = 0

        try {
            val root = JSONObject(infosJson)
            val networkInfo = root.optJSONObject("map")?.optJSONObject(instanceName) ?: return
            val running = networkInfo.optBoolean("running", false)
            stateStore.updateFromNetworkInfo(
                instanceName,
                infosJson,
                extractVirtualIpv4(networkInfo),
                running,
            )
            val peerCount = networkInfo.optJSONArray("peers")?.length() ?: 0
            val routeCount = networkInfo.optJSONArray("routes")?.length() ?: 0
            val hostname = networkInfo.optJSONObject("my_node_info")?.optString("hostname")
            val errorMessage = networkInfo.optString("error_msg")
            Log.d(
                LOG_TAG,
                "Monitor tick=$monitorTick instance=$instanceName running=$running hostname=$hostname peers=$peerCount routes=$routeCount error=$errorMessage",
            )
            logDiagnostics(networkInfo)

            if (!running) {
                notRunningTicks += 1
                Log.w(LOG_TAG, "Instance not running count=$notRunningTicks: $errorMessage")
                if (notRunningTicks >= 2) {
                    restartInstance("instance-not-running")
                }
                return
            }
            notRunningTicks = 0

            val virtualIpv4 = extractVirtualIpv4(networkInfo)
            if (virtualIpv4 == null) {
                if (monitorTick <= 3 || monitorTick % 5 == 0) {
                    Log.d(LOG_TAG, "Raw network info: $networkInfo")
                }
                Log.d(LOG_TAG, "Instance running but virtual_ipv4 not assigned yet")
                return
            }

            if (virtualIpv4 != currentIpv4) {
                currentIpv4 = virtualIpv4
                if (useAndroidVpn) {
                    vpnPlatform.restartVpnService(instanceName, virtualIpv4)
                } else {
                    Log.i(
                        LOG_TAG,
                        "EasyTier no-tun mode active; skipping Android VpnService route for IPv4=$virtualIpv4",
                    )
                }
            }
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Failed to parse network info JSON", error)
        }
    }

    private fun logDiagnostics(networkInfo: JSONObject) {
        val stunInfo = networkInfo.optJSONObject("my_node_info")?.optJSONObject("stun_info")
        Log.d(
            LOG_TAG,
            "Diagnostics virtualIpv4=${extractVirtualIpv4(networkInfo) ?: "null"} udpNat=${stunInfo?.optString("udp_nat_type", "-") ?: "-"} tcpNat=${stunInfo?.optString("tcp_nat_type", "-") ?: "-"}",
        )

        val directConnectionCountByPeer = mutableMapOf<Long, Int>()
        val peers = networkInfo.optJSONArray("peers")
        if (peers != null) {
            for (index in 0 until peers.length()) {
                val peer = peers.optJSONObject(index) ?: continue
                directConnectionCountByPeer[peer.optLong("peer_id", 0L)] =
                    peer.optJSONArray("directly_connected_conns")?.length() ?: 0
            }
        }

        val routes = networkInfo.optJSONArray("routes")
        if (routes != null) {
            for (index in 0 until routes.length()) {
                val route = routes.optJSONObject(index) ?: continue
                val peerId = route.optLong("peer_id", 0L)
                val nextHopPeerId = route.optLong("next_hop_peer_id", 0L)
                val cost = route.optInt("cost", -1)
                val latency = route.optLong("path_latency", -1L)
                val hostname = route.optString("hostname", "")
                val publicServer = route.optJSONObject("feature_flag")
                    ?.optBoolean("is_public_server", false) ?: false
                val directConnectionCount = directConnectionCountByPeer[peerId] ?: 0
                val mode = describeRouteMode(
                    cost,
                    peerId,
                    nextHopPeerId,
                    publicServer,
                    directConnectionCount,
                )
                Log.d(
                    LOG_TAG,
                    "Route[$index] host=$hostname peer=$peerId nextHop=$nextHopPeerId cost=$cost latency=${latency}ms directConns=$directConnectionCount public=$publicServer mode=$mode",
                )
            }
        }

        val events = networkInfo.optJSONArray("events")
        if (events != null && events.length() > 0) {
            for (index in maxOf(0, events.length() - 3) until events.length()) {
                Log.d(LOG_TAG, "RecentEvent[$index]=${events.optString(index)}")
            }
        }
    }

    private fun restartInstance(reason: String) {
        val config = runningConfig
        val instanceName = runningInstanceName
        if (config.isNullOrBlank() || instanceName.isNullOrBlank() || restartInProgress) {
            return
        }
        restartInProgress = true
        Log.w(LOG_TAG, "Restarting EasyTier instance after monitor failure: reason=$reason instance=$instanceName")
        try {
            runCatching { nativeRuntime.stopAllInstances() }
            if (nativeRuntime.runNetworkInstance(config) == 0) {
                currentIpv4 = null
                missingInfoTicks = 0
                notRunningTicks = 0
                Log.i(LOG_TAG, "EasyTier instance restarted: reason=$reason")
            } else {
                Log.e(
                    LOG_TAG,
                    "EasyTier instance restart failed: reason=$reason error=${nativeRuntime.getLastError()}",
                )
            }
        } catch (error: Exception) {
            Log.e(LOG_TAG, "Exception restarting EasyTier instance: reason=$reason", error)
        } finally {
            restartInProgress = false
        }
    }

    companion object {
        const val CHANNEL_NAME = "easytier_vpn"
        private const val LOG_TAG = "EasyTier"
        private const val VPN_PERMISSION_REQUEST_CODE = 4103
        private const val METHOD_PARSE_CONFIG = "parseConfig"
        private const val METHOD_START_VPN = "startVpn"
        private const val METHOD_CHECK_VPN_PERMISSION = "checkVpnPermission"
        private const val METHOD_STOP_VPN = "stopVpn"
        private const val METHOD_GET_NETWORK_INFO = "getNetworkInfo"
        private const val METHOD_GET_LAST_ERROR = "getLastError"
        private const val ARG_CONFIG = "config"
        private const val ARG_INSTANCE_NAME = "instanceName"
        private const val ARG_USE_ANDROID_VPN = "useAndroidVpn"
        private const val ERROR_INVALID_CONFIG = "INVALID_CONFIG"
        private const val ERROR_PARSE_FAILED = "PARSE_FAILED"
        private const val ERROR_START_FAILED = "START_FAILED"
        private const val ERROR_EXCEPTION = "EXCEPTION"
        private const val ERROR_VPN_PERMISSION_DENIED = "VPN_PERMISSION_DENIED"

        internal fun describeRouteMode(
            cost: Int,
            peerId: Long,
            nextHopPeerId: Long,
            publicServer: Boolean,
            directConnectionCount: Int,
        ): String {
            if (publicServer) return "public-server"
            if (cost <= 1 && directConnectionCount > 0) return "direct-lan"
            if (cost <= 1) return "p2p-direct"
            if (nextHopPeerId != 0L && nextHopPeerId != peerId) {
                return "relay-via-$nextHopPeerId"
            }
            return "relay"
        }

        internal fun extractVirtualIpv4(networkInfo: JSONObject): String? {
            val virtualIpv4 = networkInfo.optJSONObject("my_node_info")
                ?.optJSONObject("virtual_ipv4") ?: return null
            val address = virtualIpv4.optJSONObject("address") ?: return null
            if (!address.has("addr")) return null
            val normalized = address.optLong("addr") and 0xffffffffL
            val ip = listOf(
                (normalized shr 24) and 0xff,
                (normalized shr 16) and 0xff,
                (normalized shr 8) and 0xff,
                normalized and 0xff,
            ).joinToString(".")
            return "$ip/${virtualIpv4.optInt("network_length", 24)}"
        }
    }
}

internal interface EasyTierNativeRuntime {
    fun parseConfig(config: String): Int
    fun runNetworkInstance(config: String): Int
    fun stopAllInstances()
    fun collectNetworkInfos(): String?
    fun getLastError(): String?
}

private object JniEasyTierNativeRuntime : EasyTierNativeRuntime {
    override fun parseConfig(config: String): Int = EasyTierJNI.parseConfig(config)
    override fun runNetworkInstance(config: String): Int = EasyTierJNI.runNetworkInstance(config)
    override fun stopAllInstances() {
        EasyTierJNI.stopAllInstances()
    }
    override fun collectNetworkInfos(): String? = EasyTierJNI.collectNetworkInfos(10)
    override fun getLastError(): String? = EasyTierJNI.getLastError()
}

internal interface EasyTierVpnPlatform {
    fun hasVpnPermission(): Boolean
    fun requestVpnPermission(requestCode: Int)
    fun restartVpnService(instanceName: String, ipv4: String)
    fun stopVpnService(forceStop: Boolean)
}

private class AndroidEasyTierVpnPlatform(
    private val activity: Activity,
) : EasyTierVpnPlatform {
    private var preparedPermissionIntent: Intent? = null

    override fun hasVpnPermission(): Boolean {
        preparedPermissionIntent = VpnService.prepare(activity)
        return preparedPermissionIntent == null
    }

    override fun requestVpnPermission(requestCode: Int) {
        val intent = preparedPermissionIntent ?: VpnService.prepare(activity)
        preparedPermissionIntent = null
        intent?.let {
            activity.startActivityForResult(intent, requestCode)
        }
    }

    override fun restartVpnService(instanceName: String, ipv4: String) {
        activity.stopService(Intent(activity, EasyTierVpnService::class.java))
        activity.startService(Intent(activity, EasyTierVpnService::class.java).apply {
            putExtra("ipv4_address", ipv4)
            putExtra("instance_name", instanceName)
        })
        Log.i("EasyTier", "Started EasyTierVpnService with IPv4=$ipv4 routes=virtual-subnet-only")
    }

    override fun stopVpnService(forceStop: Boolean) {
        activity.startService(Intent(activity, EasyTierVpnService::class.java).apply {
            action = EasyTierVpnService.ACTION_STOP
        })
        if (forceStop) {
            activity.stopService(Intent(activity, EasyTierVpnService::class.java))
        }
    }
}

internal interface EasyTierRuntimeStateStore {
    fun markStarted(instanceName: String)
    fun updateFromNetworkInfo(
        instanceName: String,
        json: String,
        virtualIpv4: String?,
        running: Boolean,
    )
    fun refreshFromNative()
    fun clear()
}

private object AndroidEasyTierRuntimeStateStore : EasyTierRuntimeStateStore {
    override fun markStarted(instanceName: String) = EasyTierStateStore.markStarted(instanceName)

    override fun updateFromNetworkInfo(
        instanceName: String,
        json: String,
        virtualIpv4: String?,
        running: Boolean,
    ) = EasyTierStateStore.updateFromNetworkInfo(instanceName, json, virtualIpv4, running)

    override fun refreshFromNative() {
        EasyTierStateStore.refreshFromJni()
    }

    override fun clear() = EasyTierStateStore.clear()
}

internal interface EasyTierMonitorScheduler {
    fun start(task: () -> Unit)
    fun stop()
}

private class HandlerEasyTierMonitorScheduler : EasyTierMonitorScheduler {
    private val handler = Handler(Looper.getMainLooper())
    private var runnable: Runnable? = null

    override fun start(task: () -> Unit) {
        stop()
        runnable = object : Runnable {
            override fun run() {
                try {
                    task()
                } finally {
                    handler.postDelayed(this, 3000)
                }
            }
        }
        runnable?.let(handler::post)
    }

    override fun stop() {
        runnable?.let(handler::removeCallbacks)
        runnable = null
    }
}
