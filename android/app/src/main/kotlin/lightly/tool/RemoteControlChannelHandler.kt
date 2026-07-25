package lightly.tool

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Surface
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class RemoteControlChannelHandler internal constructor(
    private val sessionFactory: () -> RemoteControlNativeSession,
    private val accessibility: RemoteControlAccessibilityPlatform,
    private val screenTexture: RemoteControlScreenTexture,
    private val callbackDispatcher: RemoteControlCallbackDispatcher,
) {
    constructor(activity: Activity, renderer: FlutterRenderer) : this(
        sessionFactory = { AndroidRemoteControlNativeSession(activity) },
        accessibility = AndroidRemoteControlAccessibilityPlatform(activity),
        screenTexture = AndroidRemoteControlScreenTexture(renderer),
        callbackDispatcher = HandlerRemoteControlCallbackDispatcher(),
    )

    private var channel: MethodChannel? = null
    private var session: RemoteControlNativeSession? = null
    private var pendingScreenCaptureFps = DEFAULT_FPS
    private var pendingScreenCaptureBitrate = DEFAULT_BITRATE
    private var pendingScreenCaptureResult: MethodChannel.Result? = null

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME).also { methodChannel ->
            methodChannel.setMethodCallHandler(::handle)
        }
    }

    internal fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_START_RECEIVER -> startReceiver(call, result)
            METHOD_START_CONTROLLER -> startController(call, result)
            METHOD_STOP -> stop(result)
            METHOD_EXECUTE_COMMAND -> executeCommand(call, result)
            METHOD_SHOW_DISCONNECT_OVERLAY -> showDisconnectOverlay(call, result)
            METHOD_CHECK_ACCESSIBILITY_PERMISSION -> runResult(result) {
                accessibility.isRunning()
            }
            METHOD_OPEN_ACCESSIBILITY_SETTINGS -> runResult(result) {
                accessibility.openSettings()
                true
            }
            METHOD_GET_SCREEN_INFO -> runResult(result) {
                session?.getScreenInfo() ?: DEFAULT_SCREEN_INFO
            }
            METHOD_START_SCREEN_CAPTURE -> startScreenCapture(call, result)
            METHOD_STOP_SCREEN_CAPTURE -> runResult(result) {
                session?.stopScreenCapture()
                true
            }
            METHOD_REQUEST_KEY_FRAME -> runResult(result) {
                session?.requestKeyFrame()
                true
            }
            METHOD_UPDATE_BITRATE -> runResult(result) {
                session?.updateBitrate(
                    call.argument<Int>(ARG_BITRATE) ?: DEFAULT_BITRATE,
                )
                true
            }
            METHOD_CREATE_SCREEN_TEXTURE -> createScreenTexture(call, result)
            METHOD_DISPOSE_SCREEN_TEXTURE -> runResult(result) {
                screenTexture.dispose()
                true
            }
            METHOD_PUSH_SCREEN_FRAME -> pushScreenFrame(call, result)
            else -> result.notImplemented()
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != RemoteControlService.REQUEST_MEDIA_PROJECTION) {
            return false
        }
        val pendingResult = pendingScreenCaptureResult
        pendingScreenCaptureResult = null
        if (resultCode == Activity.RESULT_OK && data != null) {
            session?.handleMediaProjectionResult(
                resultCode,
                data,
                pendingScreenCaptureFps,
                pendingScreenCaptureBitrate,
            )
            pendingResult?.success(true)
        } else {
            pendingResult?.success(false)
        }
        return true
    }

    fun shutdown() {
        try {
            session?.stop()
        } catch (error: Exception) {
            Log.w(CHANNEL_NAME, "Failed to stop remote control service", error)
        }
        session = null
        pendingScreenCaptureResult = null
        screenTexture.dispose()
    }

    private fun startReceiver(call: MethodCall, result: MethodChannel.Result) {
        runResult(result) {
            ensureSession().startReceiver(
                call.argument<Int>(ARG_CONTROL_PORT) ?: DEFAULT_CONTROL_PORT,
                call.argument<Int>(ARG_SCREEN_PORT) ?: DEFAULT_SCREEN_PORT,
                call.argument<Int>(ARG_SCREEN_FPS) ?: DEFAULT_FPS,
                call.argument<Int>(ARG_SCREEN_BITRATE) ?: DEFAULT_BITRATE,
            )
            true
        }
    }

    private fun startController(call: MethodCall, result: MethodChannel.Result) {
        runResult(result) {
            ensureSession().startController(call.argument<String>(ARG_HOST) ?: "")
            true
        }
    }

    private fun stop(result: MethodChannel.Result) {
        runResult(result) {
            session?.stop()
            session = null
            true
        }
    }

    private fun executeCommand(call: MethodCall, result: MethodChannel.Result) {
        val command = call.argument<String>(ARG_COMMAND)
        if (command == null) {
            result.error(ERROR_INVALID_ARGUMENT, "Command is required", null)
            return
        }
        runResult(result) {
            session?.executeCommand(command)
            true
        }
    }

    private fun showDisconnectOverlay(call: MethodCall, result: MethodChannel.Result) {
        val message = call.argument<String>(ARG_MESSAGE) ?: DEFAULT_DISCONNECT_MESSAGE
        result.success(accessibility.showDisconnectOverlay(message))
    }

    private fun startScreenCapture(call: MethodCall, result: MethodChannel.Result) {
        if (pendingScreenCaptureResult != null) {
            result.error(
                ERROR_IN_PROGRESS,
                "Screen capture request already in progress",
                null,
            )
            return
        }
        val fps = call.argument<Int>(ARG_FPS) ?: DEFAULT_FPS
        val bitrate = call.argument<Int>(ARG_BITRATE) ?: DEFAULT_BITRATE
        pendingScreenCaptureFps = fps
        pendingScreenCaptureBitrate = bitrate
        pendingScreenCaptureResult = result
        try {
            ensureSession().startScreenCapture(
                fps = fps,
                bitrate = bitrate,
                onFrame = { data, isKeyFrame ->
                    callbackDispatcher.post {
                        channel?.invokeMethod(
                            METHOD_ON_SCREEN_FRAME,
                            mapOf(ARG_DATA to data, ARG_IS_KEY_FRAME to isKeyFrame),
                        )
                    }
                },
                onConfig = { sps, pps ->
                    callbackDispatcher.post {
                        channel?.invokeMethod(
                            METHOD_ON_SCREEN_CONFIG,
                            mapOf(ARG_SPS to sps, ARG_PPS to pps),
                        )
                    }
                },
            )
        } catch (error: Exception) {
            pendingScreenCaptureResult = null
            result.error(ERROR_EXCEPTION, error.message, null)
        }
    }

    private fun createScreenTexture(call: MethodCall, result: MethodChannel.Result) {
        runResult(result) {
            screenTexture.create(
                call.argument<Int>(ARG_WIDTH) ?: DEFAULT_WIDTH,
                call.argument<Int>(ARG_HEIGHT) ?: DEFAULT_HEIGHT,
            )
        }
    }

    private fun pushScreenFrame(call: MethodCall, result: MethodChannel.Result) {
        val data = call.argument<ByteArray>(ARG_DATA)
        if (data == null) {
            result.error(ERROR_INVALID_ARGS, "Data required", null)
            return
        }
        runResult(result) {
            screenTexture.pushFrame(
                data,
                call.argument<Int>(ARG_TYPE) ?: 3,
                call.argument<Long>(ARG_TIMESTAMP) ?: System.currentTimeMillis(),
            )
            true
        }
    }

    private fun ensureSession(): RemoteControlNativeSession {
        return session ?: sessionFactory().also { session = it }
    }

    private inline fun runResult(
        result: MethodChannel.Result,
        action: () -> Any?,
    ) {
        try {
            result.success(action())
        } catch (error: Exception) {
            result.error(ERROR_EXCEPTION, error.message, null)
        }
    }

    companion object {
        const val CHANNEL_NAME = "remote_control"
        private const val METHOD_START_RECEIVER = "startReceiver"
        private const val METHOD_START_CONTROLLER = "startController"
        private const val METHOD_STOP = "stop"
        private const val METHOD_EXECUTE_COMMAND = "executeCommand"
        private const val METHOD_SHOW_DISCONNECT_OVERLAY = "showDisconnectOverlay"
        private const val METHOD_CHECK_ACCESSIBILITY_PERMISSION =
            "checkAccessibilityPermission"
        private const val METHOD_OPEN_ACCESSIBILITY_SETTINGS = "openAccessibilitySettings"
        private const val METHOD_GET_SCREEN_INFO = "getScreenInfo"
        private const val METHOD_START_SCREEN_CAPTURE = "startScreenCapture"
        private const val METHOD_STOP_SCREEN_CAPTURE = "stopScreenCapture"
        private const val METHOD_REQUEST_KEY_FRAME = "requestKeyFrame"
        private const val METHOD_UPDATE_BITRATE = "updateBitrate"
        private const val METHOD_CREATE_SCREEN_TEXTURE = "createScreenTexture"
        private const val METHOD_DISPOSE_SCREEN_TEXTURE = "disposeScreenTexture"
        private const val METHOD_PUSH_SCREEN_FRAME = "pushScreenFrame"
        private const val METHOD_ON_SCREEN_FRAME = "onScreenFrame"
        private const val METHOD_ON_SCREEN_CONFIG = "onScreenConfig"
        private const val ARG_CONTROL_PORT = "controlPort"
        private const val ARG_SCREEN_PORT = "screenPort"
        private const val ARG_SCREEN_FPS = "screenFps"
        private const val ARG_SCREEN_BITRATE = "screenBitrate"
        private const val ARG_HOST = "host"
        private const val ARG_COMMAND = "command"
        private const val ARG_MESSAGE = "message"
        private const val ARG_FPS = "fps"
        private const val ARG_BITRATE = "bitrate"
        private const val ARG_WIDTH = "width"
        private const val ARG_HEIGHT = "height"
        private const val ARG_DATA = "data"
        private const val ARG_IS_KEY_FRAME = "isKeyFrame"
        private const val ARG_SPS = "sps"
        private const val ARG_PPS = "pps"
        private const val ARG_TYPE = "type"
        private const val ARG_TIMESTAMP = "timestamp"
        private const val ERROR_EXCEPTION = "EXCEPTION"
        private const val ERROR_INVALID_ARGUMENT = "INVALID_ARGUMENT"
        private const val ERROR_INVALID_ARGS = "INVALID_ARGS"
        private const val ERROR_IN_PROGRESS = "IN_PROGRESS"
        private const val DEFAULT_CONTROL_PORT = 18080
        private const val DEFAULT_SCREEN_PORT = 18081
        private const val DEFAULT_FPS = 15
        private const val DEFAULT_BITRATE = 2_000_000
        private const val DEFAULT_WIDTH = 1080
        private const val DEFAULT_HEIGHT = 2340
        private const val DEFAULT_DISCONNECT_MESSAGE = "对方已断开远程连接。"
        private val DEFAULT_SCREEN_INFO = mapOf<String, Any>(
            "width" to DEFAULT_WIDTH,
            "height" to DEFAULT_HEIGHT,
            "density" to 2.75,
        )
    }
}

internal interface RemoteControlNativeSession {
    fun startReceiver(controlPort: Int, screenPort: Int, fps: Int, bitrate: Int)
    fun startController(host: String)
    fun stop()
    fun executeCommand(command: String)
    fun getScreenInfo(): Map<String, Any>
    fun startScreenCapture(
        fps: Int,
        bitrate: Int,
        onFrame: (ByteArray, Boolean) -> Unit,
        onConfig: (ByteArray, ByteArray) -> Unit,
    )
    fun handleMediaProjectionResult(resultCode: Int, data: Intent, fps: Int, bitrate: Int)
    fun stopScreenCapture()
    fun requestKeyFrame()
    fun updateBitrate(bitrate: Int)
}

private class AndroidRemoteControlNativeSession(
    private val activity: Activity,
) : RemoteControlNativeSession {
    private val service = RemoteControlService(activity)

    override fun startReceiver(controlPort: Int, screenPort: Int, fps: Int, bitrate: Int) {
        service.startReceiver(controlPort, screenPort, fps, bitrate)
    }

    override fun startController(host: String) = service.startController(host)
    override fun stop() = service.stop()
    override fun executeCommand(command: String) = service.executeCommand(command)
    override fun getScreenInfo(): Map<String, Any> = service.getScreenInfo()

    override fun startScreenCapture(
        fps: Int,
        bitrate: Int,
        onFrame: (ByteArray, Boolean) -> Unit,
        onConfig: (ByteArray, ByteArray) -> Unit,
    ) {
        service.startScreenCapture(activity, fps, bitrate, onFrame, onConfig)
    }

    override fun handleMediaProjectionResult(
        resultCode: Int,
        data: Intent,
        fps: Int,
        bitrate: Int,
    ) = service.handleMediaProjectionResult(resultCode, data, fps, bitrate)

    override fun stopScreenCapture() = service.stopScreenCapture()
    override fun requestKeyFrame() = service.requestKeyFrame()
    override fun updateBitrate(bitrate: Int) = service.updateBitrate(bitrate)
}

internal interface RemoteControlAccessibilityPlatform {
    fun showDisconnectOverlay(message: String): Boolean
    fun isRunning(): Boolean
    fun openSettings()
}

private class AndroidRemoteControlAccessibilityPlatform(
    private val activity: Activity,
) : RemoteControlAccessibilityPlatform {
    override fun showDisconnectOverlay(message: String): Boolean {
        val service = RemoteControlAccessibilityService.instance ?: return false
        service.showDisconnectOverlay(message)
        return true
    }

    override fun isRunning(): Boolean = RemoteControlAccessibilityService.isRunning

    override fun openSettings() {
        activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
    }
}

internal interface RemoteControlScreenTexture {
    fun create(width: Int, height: Int): Long
    fun pushFrame(data: ByteArray, type: Int, timestamp: Long)
    fun dispose()
}

private class AndroidRemoteControlScreenTexture(
    private val renderer: FlutterRenderer,
) : RemoteControlScreenTexture {
    private var decoder: H264Decoder? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var pendingSps: ByteArray? = null
    private var pendingPps: ByteArray? = null

    override fun create(width: Int, height: Int): Long {
        dispose()
        val entry = renderer.createSurfaceTexture()
        textureEntry = entry
        entry.surfaceTexture().setDefaultBufferSize(width, height)
        surface = Surface(entry.surfaceTexture())
        Log.i("H264Decoder", "Created screen texture id=${entry.id()} size=${width}x$height")
        decoder = H264Decoder {}.apply {
            configure(surface!!, width, height)
        }
        return entry.id()
    }

    override fun pushFrame(data: ByteArray, type: Int, timestamp: Long) {
        val presentationTimeUs = timestamp * 1000L
        when (type) {
            0 -> handleConfigFrame(data)
            1 -> decoder?.decode(data, true, presentationTimeUs)
            else -> decoder?.decode(data, false, presentationTimeUs)
        }
    }

    override fun dispose() {
        decoder?.release()
        decoder = null
        surface?.release()
        surface = null
        textureEntry?.release()
        textureEntry = null
        pendingSps = null
        pendingPps = null
    }

    private fun handleConfigFrame(data: ByteArray) {
        val nalType = extractNalType(data)
        Log.d("H264Decoder", "Received config frame len=${data.size} nalType=$nalType")
        when (nalType) {
            7 -> {
                pendingSps = data
                pendingPps = null
            }
            8 -> pendingPps = data
        }
        val sps = pendingSps
        val pps = pendingPps
        if (sps != null && pps != null) {
            decoder?.feedConfig(sps, pps)
        }
    }

    private fun extractNalType(data: ByteArray): Int {
        if (data.isEmpty()) return -1
        var offset = 0
        if (data.size >= 4 && data[0].toInt() == 0 && data[1].toInt() == 0) {
            offset = when {
                data[2].toInt() == 1 -> 3
                data[2].toInt() == 0 && data[3].toInt() == 1 -> 4
                else -> 0
            }
        }
        if (offset >= data.size) return -1
        return data[offset].toInt() and 0x1F
    }
}

internal fun interface RemoteControlCallbackDispatcher {
    fun post(action: () -> Unit)
}

private class HandlerRemoteControlCallbackDispatcher : RemoteControlCallbackDispatcher {
    private val handler = Handler(Looper.getMainLooper())

    override fun post(action: () -> Unit) {
        handler.post(action)
    }
}
