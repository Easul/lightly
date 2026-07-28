package lightly.tool

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import lightly.tool.plugin.easytier.ipc.IEasyTierPluginService

class EasyTierChannelHandler(
    private val activity: Activity,
    private val pluginActivationCoordinator: OptionalPluginActivationCoordinator,
) {
    private data class PendingOperation(
        val result: MethodChannel.Result,
        val block: (IEasyTierPluginService) -> Unit,
    )

    private data class PendingStart(
        val config: String,
        val instanceName: String,
        val result: MethodChannel.Result,
    )

    private val pendingOperations = mutableListOf<PendingOperation>()
    private var channel: MethodChannel? = null
    private var service: IEasyTierPluginService? = null
    private var binding = false
    private var bound = false
    private var pendingStart: PendingStart? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            val connected = IEasyTierPluginService.Stub.asInterface(binder)
            val compatible = runCatching {
                connected.getApiVersion() >= MINIMUM_API_VERSION
            }.getOrDefault(false)
            if (!compatible) {
                failPending(ERROR_INCOMPATIBLE, "EasyTier plugin API is incompatible")
                disconnect()
                return
            }
            service = connected
            binding = false
            val operations = pendingOperations.toList()
            pendingOperations.clear()
            operations.forEach { operation -> execute(connected, operation) }
        }

        override fun onServiceDisconnected(name: ComponentName) = handleRemoteDisconnect()
        override fun onBindingDied(name: ComponentName) = handleRemoteDisconnect()

        override fun onNullBinding(name: ComponentName) {
            failPending(ERROR_INCOMPATIBLE, "EasyTier plugin returned a null binding")
            disconnect()
        }
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(::handle)
        }
    }

    internal fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_PARSE_CONFIG -> parseConfig(call, result)
            METHOD_START_VPN -> startVpn(call, result)
            METHOD_CHECK_VPN_PERMISSION -> withService(result) {
                result.success(it.hasVpnPermission())
            }
            METHOD_STOP_VPN -> withService(result) { result.success(it.stopNetwork()) }
            METHOD_GET_NETWORK_INFO -> withService(result) { result.success(it.getNetworkInfo()) }
            METHOD_GET_LAST_ERROR -> withService(result) { result.success(it.getLastError()) }
            else -> result.notImplemented()
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != VPN_PERMISSION_REQUEST_CODE) return false
        val pending = pendingStart ?: return true
        pendingStart = null
        if (resultCode != Activity.RESULT_OK) {
            pending.result.error(
                ERROR_VPN_PERMISSION_DENIED,
                "User denied VPN permission",
                null,
            )
            return true
        }
        withService(pending.result) { connected ->
            finishStart(connected, pending)
        }
        return true
    }

    fun shutdown() {
        channel?.setMethodCallHandler(null)
        channel = null
        pendingStart?.result?.error(ERROR_DISCONNECTED, "Activity destroyed", null)
        pendingStart = null
        failPending(ERROR_DISCONNECTED, "Activity destroyed")
        disconnect()
    }

    private fun parseConfig(call: MethodCall, result: MethodChannel.Result) {
        val config = call.argument<String>(ARG_CONFIG)
        if (config.isNullOrBlank() || config.length > MAX_CONFIG_LENGTH) {
            result.error(ERROR_INVALID_CONFIG, "Config is required", null)
            return
        }
        withService(result) { connected ->
            val parsed = connected.parseConfig(config)
            if (parsed) {
                result.success(true)
            } else {
                result.error(
                    ERROR_PARSE_FAILED,
                    connected.getLastError() ?: "Config parse failed",
                    null,
                )
            }
        }
    }

    private fun startVpn(call: MethodCall, result: MethodChannel.Result) {
        val config = call.argument<String>(ARG_CONFIG)
        val instanceName = call.argument<String>(ARG_INSTANCE_NAME)
        val useAndroidVpn = call.argument<Boolean>(ARG_USE_ANDROID_VPN) ?: true
        if (config.isNullOrBlank() ||
            config.length > MAX_CONFIG_LENGTH ||
            instanceName.isNullOrBlank()
        ) {
            result.error(ERROR_INVALID_CONFIG, "Config and instanceName are required", null)
            return
        }
        withService(result) { connected ->
            val pending = PendingStart(config, instanceName, result)
            if (useAndroidVpn && !connected.hasVpnPermission()) {
                if (pendingStart != null) {
                    result.error(ERROR_PERMISSION_BUSY, "VPN permission request already active", null)
                    return@withService
                }
                pendingStart = pending
                val permissionIntent = Intent().setComponent(
                    ComponentName(PLUGIN_PACKAGE, PLUGIN_PERMISSION_ACTIVITY_CLASS),
                )
                runCatching {
                    activity.startActivityForResult(permissionIntent, VPN_PERMISSION_REQUEST_CODE)
                }.onFailure {
                    pendingStart = null
                    result.error(ERROR_VPN_PERMISSION_DENIED, "Unable to request VPN permission", null)
                }
                return@withService
            }
            finishStart(connected, pending, useAndroidVpn)
        }
    }

    private fun finishStart(
        connected: IEasyTierPluginService,
        pending: PendingStart,
        useAndroidVpn: Boolean = true,
    ) {
        val started = connected.startNetwork(
            pending.config,
            pending.instanceName,
            useAndroidVpn,
        )
        if (started) {
            pending.result.success(true)
        } else {
            pending.result.error(
                ERROR_START_FAILED,
                connected.getLastError() ?: "EasyTier start failed",
                null,
            )
        }
    }

    private fun withService(
        result: MethodChannel.Result,
        block: (IEasyTierPluginService) -> Unit,
    ) {
        val connected = service
        if (connected != null) {
            execute(connected, PendingOperation(result, block))
            return
        }
        if (!isTrustedPluginInstalled()) {
            result.error(
                ERROR_PLUGIN_UNAVAILABLE,
                "EasyTier plugin is not installed or signature does not match",
                null,
            )
            return
        }
        pendingOperations += PendingOperation(result, block)
        if (binding) return
        binding = true
        pluginActivationCoordinator.activate(
            pluginPackage = PLUGIN_PACKAGE,
            bootstrapActivityClass = PLUGIN_BOOTSTRAP_ACTIVITY_CLASS,
            onActivated = ::bindPluginService,
            onFailure = {
                failPending(ERROR_PLUGIN_UNAVAILABLE, "Unable to activate EasyTier plugin")
            },
        )
    }

    private fun bindPluginService() {
        if (!binding) {
            return
        }
        val intent = Intent(ACTION_BIND).setComponent(
            ComponentName(PLUGIN_PACKAGE, PLUGIN_SERVICE_CLASS),
        )
        val started = runCatching {
            activity.bindService(intent, connection, Context.BIND_AUTO_CREATE)
        }.getOrDefault(false)
        if (started) {
            bound = true
        } else {
            failPending(ERROR_PLUGIN_UNAVAILABLE, "Unable to bind EasyTier plugin")
        }
    }

    private fun execute(connected: IEasyTierPluginService, operation: PendingOperation) {
        runCatching { operation.block(connected) }
            .onFailure {
                handleRemoteDisconnect()
                operation.result.error(ERROR_REMOTE_FAILURE, "EasyTier plugin request failed", null)
            }
    }

    private fun failPending(code: String, message: String) {
        binding = false
        val operations = pendingOperations.toList()
        pendingOperations.clear()
        operations.forEach { it.result.error(code, message, null) }
    }

    private fun handleRemoteDisconnect() {
        service = null
        binding = false
    }

    private fun disconnect() {
        service = null
        binding = false
        if (bound) {
            runCatching { activity.unbindService(connection) }
            bound = false
        }
    }

    private fun isTrustedPluginInstalled(): Boolean {
        return runCatching {
            activity.packageManager.checkSignatures(
                activity.packageName,
                PLUGIN_PACKAGE,
            ) == PackageManager.SIGNATURE_MATCH
        }.getOrDefault(false)
    }

    companion object {
        const val CHANNEL_NAME = "easytier_vpn"
        private const val PLUGIN_PACKAGE = "lightly.tool.plugin.easytier"
        private const val PLUGIN_SERVICE_CLASS =
            "lightly.tool.plugin.easytier.EasyTierPluginService"
        private const val PLUGIN_PERMISSION_ACTIVITY_CLASS =
            "lightly.tool.plugin.easytier.EasyTierVpnPermissionActivity"
        private const val PLUGIN_BOOTSTRAP_ACTIVITY_CLASS =
            "lightly.tool.plugin.easytier.PluginBootstrapActivity"
        private const val ACTION_BIND = "lightly.tool.plugin.easytier.BIND"
        private const val MINIMUM_API_VERSION = 2
        private const val MAX_CONFIG_LENGTH = 1024 * 1024
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
        private const val ERROR_VPN_PERMISSION_DENIED = "VPN_PERMISSION_DENIED"
        private const val ERROR_PERMISSION_BUSY = "PERMISSION_BUSY"
        private const val ERROR_PLUGIN_UNAVAILABLE = "PLUGIN_UNAVAILABLE"
        private const val ERROR_INCOMPATIBLE = "INCOMPATIBLE"
        private const val ERROR_REMOTE_FAILURE = "REMOTE_FAILURE"
        private const val ERROR_DISCONNECTED = "DISCONNECTED"
    }
}
