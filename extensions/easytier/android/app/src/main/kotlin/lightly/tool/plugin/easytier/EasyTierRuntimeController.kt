package lightly.tool.plugin.easytier

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.easytier.jni.EasyTierJNI
import org.json.JSONObject

internal class EasyTierRuntimeController(
    private val nativeRuntime: EasyTierNativeRuntime,
    private val vpnPlatform: EasyTierVpnPlatform,
    private val stateStore: EasyTierRuntimeStateStore,
    private val monitorScheduler: EasyTierMonitorScheduler,
) {
    constructor(context: Context) : this(
        nativeRuntime = JniEasyTierNativeRuntime,
        vpnPlatform = AndroidEasyTierVpnPlatform(context),
        stateStore = AndroidEasyTierRuntimeStateStore,
        monitorScheduler = HandlerEasyTierMonitorScheduler(),
    )

    private var runningInstanceName: String? = null
    private var currentIpv4: String? = null
    private var monitorTick = 0
    private var runningConfig: String? = null
    private var missingInfoTicks = 0
    private var notRunningTicks = 0
    private var restartInProgress = false
    private var useAndroidVpn = true
    private var lastError: String? = null

    @Synchronized
    fun parseConfig(config: String): Boolean {
        if (config.isBlank()) {
            lastError = "Config is required"
            return false
        }
        return runCatching { nativeRuntime.parseConfig(config) == 0 }
            .onFailure { lastError = it.message }
            .getOrDefault(false)
            .also { success ->
                if (!success && lastError == null) {
                    lastError = nativeRuntime.getLastError() ?: "Config parse failed"
                }
            }
    }

    fun hasVpnPermission(): Boolean = vpnPlatform.hasVpnPermission()

    @Synchronized
    fun startNetwork(config: String, instanceName: String, androidVpn: Boolean): Boolean {
        if (config.isBlank() || instanceName.isBlank()) {
            lastError = "Config and instanceName are required"
            return false
        }
        if (androidVpn && !vpnPlatform.hasVpnPermission()) {
            lastError = "VPN permission is required"
            return false
        }
        return runCatching {
            if (!androidVpn) {
                vpnPlatform.stopVpnService()
            }
            if (nativeRuntime.runNetworkInstance(config) != 0) {
                lastError = nativeRuntime.getLastError() ?: "EasyTier start failed"
                false
            } else {
                runningConfig = config
                useAndroidVpn = androidVpn
                lastError = null
                stateStore.markStarted(instanceName)
                startMonitor(instanceName)
                true
            }
        }.onFailure { lastError = it.message }.getOrDefault(false)
    }

    @Synchronized
    fun stopNetwork(): Boolean {
        return runCatching {
            stopMonitor()
            vpnPlatform.stopVpnService()
            nativeRuntime.stopAllInstances()
            stateStore.clear()
            runningConfig = null
            useAndroidVpn = true
            lastError = null
            true
        }.onFailure { lastError = it.message }.getOrDefault(false)
    }

    @Synchronized
    fun getNetworkInfo(): String? {
        return runCatching {
            nativeRuntime.collectNetworkInfos()?.also {
                if (it.isNotBlank()) stateStore.refreshFromNative()
            }
        }.onFailure { lastError = it.message }.getOrNull()
    }

    fun getLastError(): String? = lastError ?: nativeRuntime.getLastError()

    fun close() {
        stopNetwork()
    }

    private fun startMonitor(instanceName: String) {
        monitorScheduler.stop()
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
    }

    private fun monitorStatus() {
        val instanceName = runningInstanceName ?: return
        monitorTick += 1
        val infosJson = nativeRuntime.collectNetworkInfos()
        if (infosJson.isNullOrBlank()) {
            missingInfoTicks += 1
            Log.d(LOG_TAG, "No network info returned yet count=$missingInfoTicks")
            if (missingInfoTicks >= 4) restartInstance("missing-network-info")
            return
        }
        missingInfoTicks = 0
        try {
            val root = JSONObject(infosJson)
            val networkInfo = root.optJSONObject("map")?.optJSONObject(instanceName) ?: return
            val running = networkInfo.optBoolean("running", false)
            val virtualIpv4 = extractVirtualIpv4(networkInfo)
            stateStore.updateFromNetworkInfo(instanceName, infosJson, virtualIpv4, running)
            logDiagnostics(networkInfo)
            if (!running) {
                notRunningTicks += 1
                if (notRunningTicks >= 2) restartInstance("instance-not-running")
                return
            }
            notRunningTicks = 0
            if (virtualIpv4 == null) {
                Log.d(LOG_TAG, "Instance running but virtual_ipv4 not assigned yet")
                return
            }
            if (virtualIpv4 != currentIpv4) {
                currentIpv4 = virtualIpv4
                if (useAndroidVpn) {
                    vpnPlatform.restartVpnService(instanceName, virtualIpv4)
                } else {
                    Log.i(LOG_TAG, "EasyTier no-tun active; skipping Android VPN for $virtualIpv4")
                }
            }
        } catch (error: Exception) {
            lastError = error.message
            Log.e(LOG_TAG, "Failed to parse EasyTier network info", error)
        }
    }

    private fun restartInstance(reason: String) {
        val config = runningConfig
        val instanceName = runningInstanceName
        if (config.isNullOrBlank() || instanceName.isNullOrBlank() || restartInProgress) return
        restartInProgress = true
        try {
            runCatching { nativeRuntime.stopAllInstances() }
            if (nativeRuntime.runNetworkInstance(config) == 0) {
                currentIpv4 = null
                missingInfoTicks = 0
                notRunningTicks = 0
                Log.i(LOG_TAG, "EasyTier instance restarted: reason=$reason")
            } else {
                lastError = nativeRuntime.getLastError()
                Log.e(LOG_TAG, "EasyTier restart failed: reason=$reason error=$lastError")
            }
        } catch (error: Exception) {
            lastError = error.message
            Log.e(LOG_TAG, "Exception restarting EasyTier: reason=$reason", error)
        } finally {
            restartInProgress = false
        }
    }

    private fun logDiagnostics(networkInfo: JSONObject) {
        val peers = networkInfo.optJSONArray("peers")
        val routes = networkInfo.optJSONArray("routes")
        val hostname = networkInfo.optJSONObject("my_node_info")?.optString("hostname")
        Log.d(
            LOG_TAG,
            "Monitor tick=$monitorTick instance=$runningInstanceName hostname=$hostname peers=${peers?.length() ?: 0} routes=${routes?.length() ?: 0}",
        )
    }

    companion object {
        private const val LOG_TAG = "EasyTier"

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
    override fun stopAllInstances() { EasyTierJNI.stopAllInstances() }
    override fun collectNetworkInfos(): String? = EasyTierJNI.collectNetworkInfos(10)
    override fun getLastError(): String? = EasyTierJNI.getLastError()
}

internal interface EasyTierVpnPlatform {
    fun hasVpnPermission(): Boolean
    fun restartVpnService(instanceName: String, ipv4: String)
    fun stopVpnService()
}

private class AndroidEasyTierVpnPlatform(private val context: Context) : EasyTierVpnPlatform {
    override fun hasVpnPermission(): Boolean = VpnService.prepare(context) == null

    override fun restartVpnService(instanceName: String, ipv4: String) {
        context.startService(Intent(context, EasyTierVpnService::class.java).apply {
            putExtra("ipv4_address", ipv4)
            putExtra("instance_name", instanceName)
        })
    }

    override fun stopVpnService() {
        context.startService(Intent(context, EasyTierVpnService::class.java).apply {
            action = EasyTierVpnService.ACTION_STOP
        })
    }
}

internal interface EasyTierRuntimeStateStore {
    fun markStarted(instanceName: String)
    fun updateFromNetworkInfo(instanceName: String, json: String, virtualIpv4: String?, running: Boolean)
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
    override fun refreshFromNative() { EasyTierStateStore.refreshFromJni() }
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
                try { task() } finally { handler.postDelayed(this, 3000) }
            }
        }
        runnable?.let(handler::post)
    }

    override fun stop() {
        runnable?.let(handler::removeCallbacks)
        runnable = null
    }
}
