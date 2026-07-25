package lightly.tool

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class MainActivity : FlutterActivity() {
    private var remoteControlService: RemoteControlService? = null

    private var browserProxyChannel: MethodChannel? = null
    private val storageAccessChannelHandler by lazy { StorageAccessChannelHandler(this) }
    private val externalIntentChannelHandler by lazy { ExternalIntentChannelHandler(this) }
    private val proxyFloatingModeChannelHandler by lazy {
        ProxyFloatingModeChannelHandler(this)
    }
    private val easyTierChannelHandler by lazy { EasyTierChannelHandler(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        stopProxyFloatingButtonService()
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val attributes = window.attributes
            attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = attributes
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        stopProxyFloatingButtonService()
        val url = handleIntent(intent)
        if (url != null && browserProxyChannel != null) {
            mainHandler.post {
                browserProxyChannel?.let { channel ->
                    externalIntentChannelHandler.publishNewIntent(channel, url)
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        stopProxyFloatingButtonService()
    }

    private fun handleIntent(intent: Intent?): String? {
        val action = intent?.action
        val data = intent?.dataString
        val resolvedUrl = when {
            Intent.ACTION_VIEW == action && data != null -> data
            Intent.ACTION_SEND == action && "text/plain" == intent.type ->
                resolveSharedTextTargetUrl(intent.getStringExtra(Intent.EXTRA_TEXT))
            Intent.ACTION_PROCESS_TEXT == action ->
                resolveSharedTextTargetUrl(
                    intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
                )
            else -> null
        }

        externalIntentChannelHandler.updateInitialIntentUrl(resolvedUrl)
        if (resolvedUrl != null) {
            Log.d(logTag, "Resolved external browser input: $resolvedUrl")
        }
        return resolvedUrl
    }

    private fun resolveSharedTextTargetUrl(rawText: String?): String? {
        val sharedText = rawText?.trim()
        if (sharedText.isNullOrEmpty()) {
            return null
        }

        if (sharedText.matches(Regex("^(https?|file)://.*", RegexOption.IGNORE_CASE))) {
            return sharedText
        }

        if (sharedText.matches(Regex("^[^\\s]+\\.[^\\s]+.*$"))) {
            return if (sharedText.startsWith("localhost", ignoreCase = true) ||
                sharedText.startsWith("10.") ||
                sharedText.startsWith("127.") ||
                sharedText.startsWith("192.168.") ||
                sharedText.matches(Regex("^172\\.(1[6-9]|2[0-9]|3[0-1])\\..*"))) {
                "http://$sharedText"
            } else {
                "https://$sharedText"
            }
        }

        return "https://www.google.com/search?q=${Uri.encode(sharedText)}"
    }

    private fun stopProxyFloatingButtonService() {
        proxyFloatingModeChannelHandler.stop()
    }

    private val remoteControlChannelName = "remote_control"
    private val logTag = "BrowserProxy"
    private val mainHandler = Handler(Looper.getMainLooper())

    private var channel: MethodChannel? = null
    private var pendingScreenCaptureFps = 15
    private var pendingScreenCaptureBitrate = 2000000
    private var pendingScreenCaptureResult: MethodChannel.Result? = null
    private var screenDecoder: H264Decoder? = null
    private var screenTextureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var screenTextureSurface: Surface? = null
    private var pendingDecoderSps: ByteArray? = null
    private var pendingDecoderPps: ByteArray? = null

    private fun shutdownRemoteControlResources() {
        try {
            remoteControlService?.stop()
        } catch (e: Exception) {
            Log.w(remoteControlChannelName, "Failed to stop remote control service", e)
        }
        remoteControlService = null
        releaseScreenDecoder()
    }

    private fun shutdownEasyTierVpnResources() {
        easyTierChannelHandler.shutdown()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        FloatingVideoChannelHandler(this)
            .register(flutterEngine.dartExecutor.binaryMessenger)
        TimeOverlayChannelHandler(this)
            .register(flutterEngine.dartExecutor.binaryMessenger)
        TranslationOverlayChannelHandler(this)
            .register(flutterEngine.dartExecutor.binaryMessenger)

        browserProxyChannel = BrowserPlatformChannelHandler(
            methodHandlers = listOf(
                storageAccessChannelHandler,
                externalIntentChannelHandler,
                proxyFloatingModeChannelHandler,
            ),
        ).register(flutterEngine.dartExecutor.binaryMessenger)

        MediaScannerChannelHandler(this).register(flutterEngine.dartExecutor.binaryMessenger)

        easyTierChannelHandler.register(flutterEngine.dartExecutor.binaryMessenger)

        ProxyCoreChannelHandler().register(flutterEngine.dartExecutor.binaryMessenger)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, remoteControlChannelName)
        channel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startReceiver" -> {
                        try {
                            val controlPort = call.argument<Int>("controlPort") ?: 18080
                            val screenPort = call.argument<Int>("screenPort") ?: 18081
                            val screenFps = call.argument<Int>("screenFps") ?: 15
                            val screenBitrate = call.argument<Int>("screenBitrate") ?: 2000000

                            if (remoteControlService == null) {
                                remoteControlService = RemoteControlService(this)
                            }
                            remoteControlService!!.startReceiver(
                                controlPort, screenPort,
                                screenFps, screenBitrate,
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "startController" -> {
                        try {
                            val host = call.argument<String>("host") ?: ""

                            if (remoteControlService == null) {
                                remoteControlService = RemoteControlService(this)
                            }
                            remoteControlService!!.startController(host)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "stop" -> {
                        try {
                            remoteControlService?.stop()
                            remoteControlService = null
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "executeCommand" -> {
                        try {
                            val command = call.argument<String>("command")
                            if (command != null) {
                                remoteControlService?.executeCommand(command)
                                result.success(true)
                            } else {
                                result.error("INVALID_ARGUMENT", "Command is required", null)
                            }
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "showDisconnectOverlay" -> {
                        val message = call.argument<String>("message") ?: "对方已断开远程连接。"
                        val service = RemoteControlAccessibilityService.instance
                        if (service == null) {
                            result.success(false)
                        } else {
                            service.showDisconnectOverlay(message)
                            result.success(true)
                        }
                    }

                    "checkAccessibilityPermission" -> {
                        try {
                            val isRunning = RemoteControlAccessibilityService.isRunning
                            result.success(isRunning)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "openAccessibilitySettings" -> {
                        try {
                            val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "getScreenInfo" -> {
                        try {
                            val info = remoteControlService?.getScreenInfo() ?: mapOf(
                                "width" to 1080,
                                "height" to 2340,
                                "density" to 2.75,
                            )
                            result.success(info)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "startScreenCapture" -> {
                        try {
                            if (pendingScreenCaptureResult != null) {
                                result.error("IN_PROGRESS", "Screen capture request already in progress", null)
                                return@setMethodCallHandler
                            }
                            val fps = call.argument<Int>("fps") ?: 15
                            val bitrate = call.argument<Int>("bitrate") ?: 2000000
                            
                            if (remoteControlService == null) {
                                remoteControlService = RemoteControlService(this)
                            }
                            
                            pendingScreenCaptureFps = fps
                            pendingScreenCaptureBitrate = bitrate
                            pendingScreenCaptureResult = result
                            
                            remoteControlService!!.startScreenCapture(
                                activity = this,
                                fps = fps,
                                bitrate = bitrate,
                                onFrame = { data, isKeyFrame ->
                                    mainHandler.post {
                                        channel?.invokeMethod("onScreenFrame", mapOf(
                                            "data" to data,
                                            "isKeyFrame" to isKeyFrame,
                                        ))
                                    }
                                },
                                onConfig = { sps, pps ->
                                    mainHandler.post {
                                        channel?.invokeMethod("onScreenConfig", mapOf(
                                            "sps" to sps,
                                            "pps" to pps,
                                        ))
                                    }
                                }
                            )
                        } catch (e: Exception) {
                            pendingScreenCaptureResult = null
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "stopScreenCapture" -> {
                        try {
                            remoteControlService?.stopScreenCapture()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "requestKeyFrame" -> {
                        try {
                            remoteControlService?.requestKeyFrame()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "updateBitrate" -> {
                        try {
                            val bitrate = call.argument<Int>("bitrate") ?: 2000000
                            remoteControlService?.updateBitrate(bitrate)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "createScreenTexture" -> {
                        try {
                            releaseScreenDecoder()
                            val textureEntry = flutterEngine.renderer.createSurfaceTexture()
                            screenTextureEntry = textureEntry
                            val width = call.argument<Int>("width") ?: 1080
                            val height = call.argument<Int>("height") ?: 2340
                            textureEntry.surfaceTexture().setDefaultBufferSize(width, height)
                            screenTextureSurface = Surface(textureEntry.surfaceTexture())
                            Log.i("H264Decoder", "Created screen texture id=${textureEntry.id()} size=${width}x${height}")
                            screenDecoder = H264Decoder {}.apply {
                                configure(screenTextureSurface!!, width, height)
                            }
                            result.success(textureEntry.id())
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "disposeScreenTexture" -> {
                        try {
                            releaseScreenDecoder()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "pushScreenFrame" -> {
                        try {
                            val data = call.argument<ByteArray>("data")
                            val type = call.argument<Int>("type") ?: 3
                            val timestamp = call.argument<Long>("timestamp") ?: System.currentTimeMillis()
                            val presentationTimeUs = timestamp * 1000L
                            if (data != null) {
                                when (type) {
                                    0 -> handleDecoderConfigFrame(data)
                                    1 -> screenDecoder?.decode(data, true, presentationTimeUs)
                                    else -> screenDecoder?.decode(data, false, presentationTimeUs)
                                }
                                result.success(true)
                            } else {
                                result.error("INVALID_ARGS", "Data required", null)
                            }
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (storageAccessChannelHandler.handlePermissionResult(requestCode)) {
            return
        } else if (easyTierChannelHandler.handleActivityResult(requestCode, resultCode)) {
            return
        } else if (requestCode == RemoteControlService.REQUEST_MEDIA_PROJECTION) {
            val pendingResult = pendingScreenCaptureResult
            pendingScreenCaptureResult = null
            if (resultCode == RESULT_OK && data != null) {
                remoteControlService?.handleMediaProjectionResult(
                    resultCode, data,
                    pendingScreenCaptureFps,
                    pendingScreenCaptureBitrate
                )
                pendingResult?.success(true)
            } else {
                pendingResult?.success(false)
            }
        }
    }

    private fun handleDecoderConfigFrame(data: ByteArray) {
        val nalType = extractNalType(data)
        Log.d("H264Decoder", "Received config frame len=${data.size} nalType=$nalType")
        when (nalType) {
            7 -> {
                pendingDecoderSps = data
                pendingDecoderPps = null
            }
            8 -> pendingDecoderPps = data
        }
        val sps = pendingDecoderSps
        val pps = pendingDecoderPps
        if (sps != null && pps != null) {
            screenDecoder?.feedConfig(sps, pps)
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

    private fun releaseScreenDecoder() {
        screenDecoder?.release()
        screenDecoder = null
        screenTextureSurface?.release()
        screenTextureSurface = null
        screenTextureEntry?.release()
        screenTextureEntry = null
        pendingDecoderSps = null
        pendingDecoderPps = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        storageAccessChannelHandler.handlePermissionResult(requestCode)
    }

    override fun onDestroy() {
        shutdownRemoteControlResources()
        shutdownEasyTierVpnResources()
        super.onDestroy()
    }
}
