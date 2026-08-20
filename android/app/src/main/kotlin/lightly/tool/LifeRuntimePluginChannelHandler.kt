package lightly.tool

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import lightly.tool.plugin.liferuntime.ipc.ILifeRuntimePluginService

class LifeRuntimePluginChannelHandler(
    private val activity: Activity,
    private val pluginActivationCoordinator: OptionalPluginActivationCoordinator,
) {
    private val pendingCalls = mutableListOf<PendingCall>()
    private var channel: MethodChannel? = null
    private var service: ILifeRuntimePluginService? = null
    private var binding = false
    private var bound = false

    private data class PendingCall(
        val call: MethodCall,
        val result: MethodChannel.Result,
    )

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            val connected = ILifeRuntimePluginService.Stub.asInterface(binder)
            val compatible = runCatching {
                connected.getApiVersion() >= MINIMUM_API_VERSION
            }.getOrDefault(false)
            if (!compatible) {
                failPending(ERROR_INCOMPATIBLE, "Life Runtime plugin API is incompatible")
                disconnect()
                return
            }
            service = connected
            binding = false
            val calls = pendingCalls.toList()
            pendingCalls.clear()
            calls.forEach { execute(connected, it.call, it.result) }
        }

        override fun onServiceDisconnected(name: ComponentName) = handleRemoteDisconnect()
        override fun onBindingDied(name: ComponentName) = handleRemoteDisconnect()

        override fun onNullBinding(name: ComponentName) {
            failPending(ERROR_DISCONNECTED, "Life Runtime plugin returned a null binding")
            disconnect()
        }
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(::handle)
        }
    }

    fun shutdown() {
        channel?.setMethodCallHandler(null)
        channel = null
        failPending(ERROR_DISCONNECTED, "Activity destroyed")
        disconnect()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val connected = service
        if (connected != null) {
            execute(connected, call, result)
            return
        }
        if (call.method !in CONNECTED_METHODS) {
            result.notImplemented()
            return
        }
        pendingCalls += PendingCall(call, result)
        if (binding) return
        if (!isTrustedPluginInstalled()) {
            failPending(ERROR_UNAVAILABLE, "Life Runtime plugin is not installed or trusted")
            return
        }
        binding = true
        pluginActivationCoordinator.activate(
            pluginPackage = PLUGIN_PACKAGE,
            bootstrapActivityClass = PLUGIN_BOOTSTRAP_ACTIVITY_CLASS,
            onActivated = ::bindPluginService,
            onFailure = {
                binding = false
                failPending(ERROR_UNAVAILABLE, "Unable to activate Life Runtime plugin")
            },
        )
    }

    private fun execute(
        connected: ILifeRuntimePluginService,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            when (call.method) {
                METHOD_START -> {
                    val serviceId = call.argument<String>(ARG_SERVICE_ID)
                    val optionsJson = call.argument<String>(ARG_OPTIONS_JSON) ?: "{}"
                    if (serviceId.isNullOrBlank() || optionsJson.length > MAX_OPTIONS_LENGTH) {
                        result.error(ERROR_INVALID_ARGUMENTS, "Valid service ID and options are required", null)
                    } else {
                        result.success(connected.start(serviceId, optionsJson))
                    }
                }
                METHOD_STOP -> {
                    val serviceId = call.argument<String>(ARG_SERVICE_ID)
                    if (serviceId.isNullOrBlank()) {
                        result.error(ERROR_INVALID_ARGUMENTS, "Service ID is required", null)
                    } else {
                        result.success(connected.stop(serviceId))
                    }
                }
                METHOD_STATUS -> result.success(connected.getStatus())
                METHOD_READ_CONFIG_FILES -> result.success(connected.readConfigFiles())
                METHOD_WRITE_CONFIG_FILES -> {
                    val configJson = call.argument<String>(ARG_CONFIG_JSON) ?: "{}"
                    if (configJson.length > MAX_OPTIONS_LENGTH) {
                        result.error(ERROR_INVALID_ARGUMENTS, "Runtime config is too large", null)
                    } else {
                        result.success(connected.writeConfigFiles(configJson))
                    }
                }
                METHOD_STOP_ALL -> {
                    connected.stopAll()
                    result.success(null)
                }
                METHOD_EXPORT -> {
                    val path = call.argument<String>(ARG_PATH)
                    val configJson = call.argument<String>(ARG_CONFIG_JSON) ?: "{}"
                    if (path.isNullOrBlank() || configJson.length > MAX_OPTIONS_LENGTH) {
                        result.error(ERROR_INVALID_ARGUMENTS, "Export path and config are required", null)
                    } else {
                        result.success(
                            withFileDescriptor(
                                path,
                                ParcelFileDescriptor.MODE_CREATE or
                                    ParcelFileDescriptor.MODE_TRUNCATE or
                                    ParcelFileDescriptor.MODE_WRITE_ONLY,
                            ) { connected.exportData(it, configJson) },
                        )
                    }
                }
                METHOD_IMPORT -> {
                    val path = call.argument<String>(ARG_PATH)
                    if (path.isNullOrBlank()) {
                        result.error(ERROR_INVALID_ARGUMENTS, "Import path is required", null)
                    } else {
                        result.success(
                            withFileDescriptor(path, ParcelFileDescriptor.MODE_READ_ONLY) {
                                connected.importData(it)
                            },
                        )
                    }
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error(ERROR_RUNTIME, error.message, null)
        }
    }

    private fun <T> withFileDescriptor(
        path: String,
        mode: Int,
        block: (ParcelFileDescriptor) -> T,
    ): T {
        val file = java.io.File(path).canonicalFile
        file.parentFile?.mkdirs()
        return ParcelFileDescriptor.open(file, mode).use(block)
    }

    private fun bindPluginService() {
        if (!binding) return
        val intent = Intent(ACTION_BIND).setComponent(
            ComponentName(PLUGIN_PACKAGE, PLUGIN_SERVICE_CLASS),
        )
        val started = runCatching {
            activity.bindService(intent, connection, Context.BIND_AUTO_CREATE)
        }.getOrDefault(false)
        if (!started) {
            binding = false
            failPending(ERROR_UNAVAILABLE, "Unable to bind Life Runtime plugin")
        } else bound = true
    }

    private fun disconnect() {
        binding = false
        service = null
        if (bound) {
            runCatching { activity.unbindService(connection) }
            bound = false
        }
    }

    private fun handleRemoteDisconnect() {
        failPending(ERROR_DISCONNECTED, "Life Runtime plugin disconnected")
        disconnect()
    }

    private fun failPending(code: String, message: String) {
        val calls = pendingCalls.toList()
        pendingCalls.clear()
        calls.forEach { it.result.error(code, message, null) }
    }

    private fun isTrustedPluginInstalled(): Boolean {
        return runCatching {
            activity.packageManager.checkSignatures(
                activity.packageName,
                PLUGIN_PACKAGE,
            ) == android.content.pm.PackageManager.SIGNATURE_MATCH
        }.getOrDefault(false)
    }

    companion object {
        const val CHANNEL_NAME = "life_runtime_plugin"
        private const val PLUGIN_PACKAGE = "lightly.tool.plugin.liferuntime"
        private const val PLUGIN_SERVICE_CLASS =
            "lightly.tool.plugin.liferuntime.LifeRuntimePluginService"
        private const val PLUGIN_BOOTSTRAP_ACTIVITY_CLASS =
            "lightly.tool.plugin.liferuntime.PluginBootstrapActivity"
        private const val ACTION_BIND = "lightly.tool.plugin.liferuntime.BIND"
        private const val MINIMUM_API_VERSION = 3
        private const val MAX_OPTIONS_LENGTH = 16 * 1024
        private const val ERROR_INCOMPATIBLE = "INCOMPATIBLE"
        private const val ERROR_UNAVAILABLE = "UNAVAILABLE"
        private const val ERROR_DISCONNECTED = "DISCONNECTED"
        private const val ERROR_INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
        private const val ERROR_RUNTIME = "RUNTIME_ERROR"
        private const val METHOD_START = "start"
        private const val METHOD_STOP = "stop"
        private const val METHOD_STATUS = "status"
        private const val METHOD_READ_CONFIG_FILES = "readConfigFiles"
        private const val METHOD_WRITE_CONFIG_FILES = "writeConfigFiles"
        private const val METHOD_STOP_ALL = "stopAll"
        private const val METHOD_EXPORT = "export"
        private const val METHOD_IMPORT = "import"
        private const val ARG_SERVICE_ID = "serviceId"
        private const val ARG_OPTIONS_JSON = "optionsJson"
        private const val ARG_PATH = "path"
        private const val ARG_CONFIG_JSON = "configJson"
        private val CONNECTED_METHODS = setOf(
            METHOD_START,
            METHOD_STOP,
            METHOD_STATUS,
            METHOD_READ_CONFIG_FILES,
            METHOD_WRITE_CONFIG_FILES,
            METHOD_STOP_ALL,
            METHOD_EXPORT,
            METHOD_IMPORT,
        )
    }
}
