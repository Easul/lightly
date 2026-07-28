package lightly.tool.plugin.easytier

import com.easytier.jni.EasyTierJNI
import org.json.JSONObject

object EasyTierStateStore {
    const val PATH_NETWORK_INFO = "network_info"
    const val COLUMN_INSTANCE_NAME = "instance_name"
    const val COLUMN_RAW_NETWORK_INFO_JSON = "raw_network_info_json"
    const val COLUMN_VIRTUAL_IPV4 = "virtual_ipv4"
    const val COLUMN_UPDATED_AT = "updated_at"
    const val COLUMN_IS_RUNNING = "is_running"
    const val COLUMN_ERROR_MESSAGE = "error_message"

    private val lock = Any()

    fun authorityFor(packageName: String): String = "$packageName.easytier"

    @Volatile private var instanceName: String? = null
    @Volatile private var rawNetworkInfoJson: String? = null
    @Volatile private var virtualIpv4: String? = null
    @Volatile private var updatedAtMillis: Long = 0L
    @Volatile private var isRunning: Boolean = false
    @Volatile private var errorMessage: String? = null

    data class Snapshot(
        val instanceName: String?,
        val rawNetworkInfoJson: String?,
        val virtualIpv4: String?,
        val updatedAtMillis: Long,
        val isRunning: Boolean,
        val errorMessage: String?,
    )

    fun markStarted(nextInstanceName: String) {
        synchronized(lock) {
            instanceName = nextInstanceName
            isRunning = true
            errorMessage = null
            updatedAtMillis = System.currentTimeMillis()
        }
    }

    fun updateFromNetworkInfo(
        nextInstanceName: String?,
        json: String?,
        nextVirtualIpv4: String?,
        running: Boolean,
    ) {
        synchronized(lock) {
            if (!nextInstanceName.isNullOrBlank()) {
                instanceName = nextInstanceName
            }
            rawNetworkInfoJson = json
            virtualIpv4 = nextVirtualIpv4
            isRunning = running
            errorMessage = null
            updatedAtMillis = System.currentTimeMillis()
        }
    }

    fun setError(message: String?) {
        synchronized(lock) {
            errorMessage = message
            updatedAtMillis = System.currentTimeMillis()
        }
    }

    fun clear() {
        synchronized(lock) {
            instanceName = null
            rawNetworkInfoJson = null
            virtualIpv4 = null
            updatedAtMillis = System.currentTimeMillis()
            isRunning = false
            errorMessage = null
        }
    }

    fun refreshFromJni(): Snapshot {
        val currentInstanceName = instanceName
        return try {
            val info = EasyTierJNI.collectNetworkInfos(10)
            if (!info.isNullOrBlank()) {
                val root = JSONObject(info)
                val resolvedInstanceName = resolveInstanceName(root, currentInstanceName)
                val networkInfo = resolvedInstanceName?.let { name ->
                    root.optJSONObject("map")?.optJSONObject(name)
                }
                updateFromNetworkInfo(
                    resolvedInstanceName,
                    info,
                    networkInfo?.let(::extractVirtualIpv4),
                    networkInfo?.optBoolean("running", false) ?: false,
                )
            }
            snapshot()
        } catch (error: Throwable) {
            setError(error.message)
            snapshot()
        }
    }

    fun snapshot(): Snapshot {
        synchronized(lock) {
            return Snapshot(
                instanceName = instanceName,
                rawNetworkInfoJson = rawNetworkInfoJson,
                virtualIpv4 = virtualIpv4,
                updatedAtMillis = updatedAtMillis,
                isRunning = isRunning,
                errorMessage = errorMessage,
            )
        }
    }

    private fun resolveInstanceName(root: JSONObject, preferredInstanceName: String?): String? {
        val map = root.optJSONObject("map") ?: return preferredInstanceName
        if (!preferredInstanceName.isNullOrBlank() && map.has(preferredInstanceName)) {
            return preferredInstanceName
        }
        val keys = map.keys()
        return if (keys.hasNext()) keys.next() else preferredInstanceName
    }

    private fun extractVirtualIpv4(networkInfo: JSONObject): String? {
        val myNodeInfo = networkInfo.optJSONObject("my_node_info") ?: return null
        val virtualIpv4 = myNodeInfo.optJSONObject("virtual_ipv4") ?: return null
        val addressObj = virtualIpv4.optJSONObject("address") ?: return null
        if (!addressObj.has("addr")) {
            return null
        }

        val addr = addressObj.optLong("addr")
        val networkLength = virtualIpv4.optInt("network_length", 24)
        val normalized = addr and 0xffffffffL
        val ip = listOf(
            (normalized shr 24) and 0xff,
            (normalized shr 16) and 0xff,
            (normalized shr 8) and 0xff,
            normalized and 0xff,
        ).joinToString(".")

        return "$ip/$networkLength"
    }
}
