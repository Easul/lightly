package lightly.tool

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import lightly.tool.plugin.telegram.ipc.ITelegramPluginCallback
import lightly.tool.plugin.telegram.ipc.ITelegramPluginService

class TelegramPluginChannelHandler(
    private val activity: Activity,
    private val pluginActivationCoordinator: OptionalPluginActivationCoordinator,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val connectWaiters = mutableListOf<MethodChannel.Result>()
    private var channel: MethodChannel? = null
    private var service: ITelegramPluginService? = null
    private var binding = false
    private var bound = false

    private val callback = object : ITelegramPluginCallback.Stub() {
        override fun onResult(resultJson: String) {
            if (resultJson.length > MAX_JSON_LENGTH) {
                return
            }
            mainHandler.post {
                channel?.invokeMethod(METHOD_ON_RESULT, resultJson)
            }
        }
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            val connected = ITelegramPluginService.Stub.asInterface(binder)
            val compatible = runCatching {
                connected.getApiVersion() >= MINIMUM_API_VERSION
            }.getOrDefault(false)
            if (!compatible) {
                finishConnect(false)
                disconnect()
                return
            }
            service = connected
            runCatching { connected.registerCallback(callback) }
                .onSuccess { finishConnect(true) }
                .onFailure {
                    service = null
                    finishConnect(false)
                    disconnect()
                }
        }

        override fun onServiceDisconnected(name: ComponentName) {
            handleRemoteDisconnect()
        }

        override fun onBindingDied(name: ComponentName) {
            handleRemoteDisconnect()
        }

        override fun onNullBinding(name: ComponentName) {
            finishConnect(false)
            disconnect()
        }
    }

    fun register(messenger: BinaryMessenger): MethodChannel {
        return MethodChannel(messenger, CHANNEL_NAME).also { registeredChannel ->
            channel = registeredChannel
            registeredChannel.setMethodCallHandler(::handle)
        }
    }

    fun shutdown() {
        channel?.setMethodCallHandler(null)
        channel = null
        disconnect()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_CONNECT -> connect(result)
            METHOD_CREATE_CLIENT -> withService(result) { it.createClient() }
            METHOD_SEND -> send(call, result)
            METHOD_EXECUTE -> execute(call, result)
            METHOD_DISCONNECT -> {
                disconnect()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun connect(result: MethodChannel.Result) {
        if (service != null) {
            result.success(true)
            return
        }
        connectWaiters += result
        if (binding) {
            return
        }
        if (!isTrustedPluginInstalled()) {
            finishConnect(false)
            return
        }
        binding = true
        pluginActivationCoordinator.activate(
            pluginPackage = PLUGIN_PACKAGE,
            bootstrapActivityClass = PLUGIN_BOOTSTRAP_ACTIVITY_CLASS,
            onActivated = ::bindPluginService,
            onFailure = { finishConnect(false) },
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
        if (!started) {
            finishConnect(false)
        } else {
            bound = true
        }
    }

    private fun send(call: MethodCall, result: MethodChannel.Result) {
        val clientId = call.argument<Int>(ARG_CLIENT_ID)
        val requestJson = call.argument<String>(ARG_REQUEST_JSON)
        if (clientId == null || requestJson.isNullOrBlank() || requestJson.length > MAX_JSON_LENGTH) {
            result.error(ERROR_INVALID_ARGUMENTS, "Valid client ID and request JSON are required", null)
            return
        }
        withService(result) {
            it.send(clientId, requestJson)
            null
        }
    }

    private fun execute(call: MethodCall, result: MethodChannel.Result) {
        val requestJson = call.argument<String>(ARG_REQUEST_JSON)
        if (requestJson.isNullOrBlank() || requestJson.length > MAX_JSON_LENGTH) {
            result.error(ERROR_INVALID_ARGUMENTS, "Valid request JSON is required", null)
            return
        }
        withService(result) { it.execute(requestJson) }
    }

    private fun withService(
        result: MethodChannel.Result,
        block: (ITelegramPluginService) -> Any?,
    ) {
        val connected = service
        if (connected == null) {
            result.error(ERROR_NOT_CONNECTED, "Telegram plugin is not connected", null)
            return
        }
        runCatching { block(connected) }
            .onSuccess(result::success)
            .onFailure {
                handleRemoteDisconnect()
                result.error(ERROR_REMOTE_FAILURE, "Telegram plugin request failed", null)
            }
    }

    private fun finishConnect(success: Boolean) {
        binding = false
        val waiters = connectWaiters.toList()
        connectWaiters.clear()
        waiters.forEach { it.success(success) }
    }

    private fun handleRemoteDisconnect() {
        service = null
        binding = false
        mainHandler.post {
            channel?.invokeMethod(METHOD_ON_DISCONNECTED, null)
        }
    }

    private fun disconnect() {
        service?.let { connected ->
            runCatching { connected.unregisterCallback(callback) }
        }
        service = null
        binding = false
        if (bound) {
            runCatching { activity.unbindService(connection) }
            bound = false
        }
        finishConnect(false)
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
        const val CHANNEL_NAME = "telegram_plugin"
        private const val PLUGIN_PACKAGE = "lightly.tool.plugin.telegram"
        private const val PLUGIN_SERVICE_CLASS =
            "lightly.tool.plugin.telegram.TelegramPluginService"
        private const val PLUGIN_BOOTSTRAP_ACTIVITY_CLASS =
            "lightly.tool.plugin.telegram.PluginBootstrapActivity"
        private const val ACTION_BIND = "lightly.tool.plugin.telegram.BIND"
        private const val MINIMUM_API_VERSION = 2
        private const val MAX_JSON_LENGTH = 512 * 1024
        private const val METHOD_CONNECT = "connect"
        private const val METHOD_CREATE_CLIENT = "createClient"
        private const val METHOD_SEND = "send"
        private const val METHOD_EXECUTE = "execute"
        private const val METHOD_DISCONNECT = "disconnect"
        private const val METHOD_ON_RESULT = "onResult"
        private const val METHOD_ON_DISCONNECTED = "onDisconnected"
        private const val ARG_CLIENT_ID = "clientId"
        private const val ARG_REQUEST_JSON = "requestJson"
        private const val ERROR_INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
        private const val ERROR_NOT_CONNECTED = "NOT_CONNECTED"
        private const val ERROR_REMOTE_FAILURE = "REMOTE_FAILURE"
    }
}
