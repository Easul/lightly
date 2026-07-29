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
import lightly.tool.plugin.webrtc.ipc.IWebRtcVoicePluginCallback
import lightly.tool.plugin.webrtc.ipc.IWebRtcVoicePluginService

class WebRtcVoicePluginChannelHandler(
    private val activity: Activity,
    private val pluginActivationCoordinator: OptionalPluginActivationCoordinator,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val connectWaiters = mutableListOf<MethodChannel.Result>()
    private var channel: MethodChannel? = null
    private var service: IWebRtcVoicePluginService? = null
    private var binding = false
    private var bound = false
    private var permissionResult: MethodChannel.Result? = null

    private val callback = object : IWebRtcVoicePluginCallback.Stub() {
        override fun onEvent(eventJson: String) {
            if (eventJson.length > MAX_JSON_LENGTH) {
                return
            }
            mainHandler.post { channel?.invokeMethod(METHOD_ON_EVENT, eventJson) }
        }
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            val connected = IWebRtcVoicePluginService.Stub.asInterface(binder)
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

        override fun onServiceDisconnected(name: ComponentName) = handleRemoteDisconnect()
        override fun onBindingDied(name: ComponentName) = handleRemoteDisconnect()

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

    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_AUDIO_PERMISSION) {
            return false
        }
        permissionResult?.success(resultCode == Activity.RESULT_OK)
        permissionResult = null
        return true
    }

    fun shutdown() {
        permissionResult?.error(ERROR_DISCONNECTED, "Activity destroyed", null)
        permissionResult = null
        channel?.setMethodCallHandler(null)
        channel = null
        disconnect()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_CONNECT -> connect(result)
            METHOD_REQUEST -> request(call, result)
            METHOD_REQUEST_AUDIO_PERMISSION -> requestAudioPermission(result)
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

    private fun request(call: MethodCall, result: MethodChannel.Result) {
        val requestJson = call.argument<String>(ARG_REQUEST_JSON)
        if (requestJson.isNullOrBlank() || requestJson.length > MAX_JSON_LENGTH) {
            result.error(ERROR_INVALID_ARGUMENTS, "Valid request JSON is required", null)
            return
        }
        val connected = service
        if (connected == null) {
            result.error(ERROR_NOT_CONNECTED, "WebRTC voice plugin is not connected", null)
            return
        }
        runCatching { connected.request(requestJson) }
            .onSuccess { result.success(null) }
            .onFailure {
                handleRemoteDisconnect()
                result.error(ERROR_REMOTE_FAILURE, "WebRTC voice plugin request failed", null)
            }
    }

    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (!isTrustedPluginInstalled()) {
            result.error(ERROR_NOT_CONNECTED, "WebRTC voice plugin is unavailable", null)
            return
        }
        if (permissionResult != null) {
            result.error(ERROR_PERMISSION_BUSY, "Audio permission request already active", null)
            return
        }
        permissionResult = result
        val intent = Intent().setComponent(
            ComponentName(PLUGIN_PACKAGE, PLUGIN_PERMISSION_ACTIVITY_CLASS),
        )
        runCatching { activity.startActivityForResult(intent, REQUEST_AUDIO_PERMISSION) }
            .onFailure {
                permissionResult = null
                result.error(ERROR_PERMISSION, "Unable to request plugin audio permission", null)
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
        mainHandler.post { channel?.invokeMethod(METHOD_ON_DISCONNECTED, null) }
    }

    private fun disconnect() {
        service?.let { connected -> runCatching { connected.unregisterCallback(callback) } }
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
        const val CHANNEL_NAME = "webrtc_voice_plugin"
        private const val PLUGIN_PACKAGE = "lightly.tool.plugin.webrtc"
        private const val PLUGIN_SERVICE_CLASS =
            "lightly.tool.plugin.webrtc.WebRtcVoicePluginService"
        private const val PLUGIN_PERMISSION_ACTIVITY_CLASS =
            "lightly.tool.plugin.webrtc.AudioPermissionActivity"
        private const val PLUGIN_BOOTSTRAP_ACTIVITY_CLASS =
            "lightly.tool.plugin.webrtc.PluginBootstrapActivity"
        private const val ACTION_BIND = "lightly.tool.plugin.webrtc.BIND"
        private const val MINIMUM_API_VERSION = 3
        private const val MAX_JSON_LENGTH = 512 * 1024
        private const val REQUEST_AUDIO_PERMISSION = 49013
        private const val METHOD_CONNECT = "connect"
        private const val METHOD_REQUEST = "request"
        private const val METHOD_REQUEST_AUDIO_PERMISSION = "requestAudioPermission"
        private const val METHOD_DISCONNECT = "disconnect"
        private const val METHOD_ON_EVENT = "onEvent"
        private const val METHOD_ON_DISCONNECTED = "onDisconnected"
        private const val ARG_REQUEST_JSON = "requestJson"
        private const val ERROR_INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
        private const val ERROR_NOT_CONNECTED = "NOT_CONNECTED"
        private const val ERROR_REMOTE_FAILURE = "REMOTE_FAILURE"
        private const val ERROR_DISCONNECTED = "DISCONNECTED"
        private const val ERROR_PERMISSION = "PERMISSION"
        private const val ERROR_PERMISSION_BUSY = "PERMISSION_BUSY"
    }
}
