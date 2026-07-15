package lightly.tool

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Surface
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import com.easytier.jni.EasyTierJNI
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import org.json.JSONObject
import java.util.concurrent.Executor

class MainActivity : FlutterActivity() {
    private val manageStorageRequestCode = 4101
    private val readStorageRequestCode = 4102
    private val vpnPermissionRequestCode = 4103
    private var pendingStoragePermissionResult: MethodChannel.Result? = null
    private var pendingVpnPermissionResult: MethodChannel.Result? = null
    private var pendingVpnConfig: String? = null
    private var pendingVpnInstanceName: String? = null
    private val easyTierMonitorHandler = Handler(Looper.getMainLooper())
    private var easyTierMonitorRunnable: Runnable? = null
    private var easyTierRunningInstanceName: String? = null
    private var easyTierCurrentIpv4: String? = null
    private var easyTierMonitorTick = 0
    private var easyTierRunningConfig: String? = null
    private var easyTierMissingInfoTicks = 0
    private var easyTierNotRunningTicks = 0
    private var easyTierRestartInProgress = false
    private var easyTierUseAndroidVpn = true
    private var remoteControlService: RemoteControlService? = null

    private var initialIntentUrl: String? = null
    private var browserProxyChannel: MethodChannel? = null
    private val browserImportedFileService by lazy {
        BrowserImportedFileService(this, logTag)
    }

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
                browserProxyChannel?.invokeMethod("onNewIntentUrl", mapOf("url" to url))
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

        initialIntentUrl = resolvedUrl
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
        runCatching {
            stopService(Intent(this, ProxyFloatingButtonService::class.java))
        }
    }

    private val channelName = "browser_proxy"
    private val easyTierChannelName = "easytier_vpn"
    private val remoteControlChannelName = "remote_control"
    private val logTag = "BrowserProxy"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: Executor by lazy {
        Executor { runnable ->
            if (Looper.myLooper() == Looper.getMainLooper()) {
                runnable.run()
            } else {
                mainHandler.post(runnable)
            }
        }
    }
    
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
        try {
            stopEasyTierMonitor()
            val intent = Intent(this, EasyTierVpnService::class.java).apply {
                action = EasyTierVpnService.ACTION_STOP
            }
            startService(intent)
        } catch (e: Exception) {
            Log.w(easyTierChannelName, "Failed to stop EasyTier VPN service", e)
        }

        try {
            EasyTierJNI.stopAllInstances()
            easyTierRunningConfig = null
        } catch (e: Exception) {
            Log.w(easyTierChannelName, "Failed to stop EasyTier instances", e)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        FloatingVideoChannelHandler(this)
            .register(flutterEngine.dartExecutor.binaryMessenger)

        browserProxyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        browserProxyChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> {
                        Log.d(logTag, "Checking proxy override support")
                        result.success(WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE))
                    }

                    "setProxy" -> {
                        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
                            result.error("UNSUPPORTED", "WebView proxy override is not supported", null)
                            return@setMethodCallHandler
                        }

                        val host = call.argument<String>("host")
                        val port = call.argument<Int>("port")
                        val scheme = call.argument<String>("scheme") ?: "http"
                        val bypassDomains = call.argument<List<String>>("bypassDomains") ?: emptyList()

                        if (host.isNullOrBlank() || port == null) {
                            Log.e(logTag, "Invalid proxy arguments: host=$host port=$port")
                            result.error("INVALID_ARGUMENTS", "Host and port are required", null)
                            return@setMethodCallHandler
                        }

                        val normalizedScheme = scheme.lowercase()
                        val proxyRule = "$normalizedScheme://$host:$port"
                        Log.d(logTag, "Applying proxy rule: $proxyRule")
                        val proxyConfigBuilder = ProxyConfig.Builder()
                            .addProxyRule(proxyRule)
                            .addDirect()
                            .addBypassRule("localhost")
                            .addBypassRule("127.0.0.1")
                            .addBypassRule("127.*")
                            .addBypassRule("::1")

                        bypassDomains
                            .map { it.trim().lowercase() }
                            .filter { it.isNotEmpty() }
                            .forEach { domain ->
                                proxyConfigBuilder.addBypassRule(domain)
                            }

                        val proxyConfig = proxyConfigBuilder.build()

                        ProxyController.getInstance().setProxyOverride(proxyConfig, executor) {
                            Log.d(logTag, "Proxy override applied")
                            result.success(true)
                        }
                    }

                    "clearProxy" -> {
                        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
                            Log.d(logTag, "Proxy override unsupported while clearing")
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        ProxyController.getInstance().clearProxyOverride(executor) {
                            Log.d(logTag, "Proxy override cleared")
                            result.success(true)
                        }
                    }

                    "getSharedDownloadsPath" -> {
                        result.success(
                            Environment.getExternalStoragePublicDirectory(
                                Environment.DIRECTORY_DOWNLOADS
                            ).absolutePath
                        )
                    }

                    "hasFileAccessPermission" -> {
                        result.success(hasFileAccessPermission())
                    }

                    "requestFileAccessPermission" -> {
                        if (pendingStoragePermissionResult != null) {
                            result.error("IN_PROGRESS", "Storage permission request already in progress", null)
                            return@setMethodCallHandler
                        }

                        if (hasFileAccessPermission()) {
                            result.success(true)
                            return@setMethodCallHandler
                        }

                        pendingStoragePermissionResult = result
                        requestFileAccessPermission()
                    }

                    "getInitialIntentUrl" -> {
                        val url = initialIntentUrl
                        initialIntentUrl = null
                        result.success(url)
                    }

                    "detachExternalIntent" -> {
                        initialIntentUrl = null
                        setIntent(Intent(this, MainActivity::class.java).apply {
                            action = Intent.ACTION_MAIN
                            addCategory(Intent.CATEGORY_LAUNCHER)
                        })
                        result.success(true)
                    }

                    "importContentUriToPrivateFile" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString.isNullOrBlank()) {
                            result.error("INVALID_URI", "URI is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(
                                browserImportedFileService.importContentUriToPrivateFile(uriString),
                            )
                        } catch (e: Exception) {
                            Log.e(logTag, "Failed to import content URI: $uriString", e)
                            result.error("IMPORT_FAILED", e.message, null)
                        }
                    }

                    "getContentMimeType" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString.isNullOrBlank()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(browserImportedFileService.getContentMimeType(uriString))
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }

                    "cleanupImportedPrivateFiles" -> {
                        val retainedUrls =
                            call.argument<List<String>>("retainedUrls") ?: emptyList()
                        try {
                            result.success(
                                browserImportedFileService.cleanupImportedPrivateFiles(retainedUrls),
                            )
                        } catch (e: Exception) {
                            Log.e(logTag, "Failed to cleanup imported private files", e)
                            result.error("CLEANUP_FAILED", e.message, null)
                        }
                    }

                    "startProxyFloatingButtonMode" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                            val permissionIntent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName"),
                            )
                            startActivity(permissionIntent)
                            result.success("permission_required")
                            return@setMethodCallHandler
                        }

                        val serviceIntent = Intent(this, ProxyFloatingButtonService::class.java)
                        ContextCompat.startForegroundService(this, serviceIntent)
                        moveTaskToBack(true)
                        result.success("started")
                    }

                    "stopProxyFloatingButtonMode" -> {
                        stopProxyFloatingButtonService()
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }

        MediaScannerChannelHandler(this).register(flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, easyTierChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "parseConfig" -> {
                        val config = call.argument<String>("config")
                        if (config.isNullOrBlank()) {
                            result.error("INVALID_CONFIG", "Config is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val res = EasyTierJNI.parseConfig(config)
                            if (res == 0) {
                                result.success(true)
                            } else {
                                val error = EasyTierJNI.getLastError()
                                result.error("PARSE_FAILED", error ?: "Config parse failed", null)
                            }
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "startVpn" -> {
                        val config = call.argument<String>("config")
                        val instanceName = call.argument<String>("instanceName")
                        val useAndroidVpn = call.argument<Boolean>("useAndroidVpn") ?: true
                        Log.d("EasyTier", "startVpn called with config length: ${config?.length ?: 0}")
                        
                        if (config.isNullOrBlank() || instanceName.isNullOrBlank()) {
                            Log.e("EasyTier", "Config is null or blank")
                            result.error("INVALID_CONFIG", "Config and instanceName are required", null)
                            return@setMethodCallHandler
                        }

                        if (!useAndroidVpn) {
                            Log.d("EasyTier", "Starting EasyTier without Android VpnService")
                            stopEasyTierVpnService()
                            startVpnWithConfig(config, instanceName, result, useAndroidVpn = false)
                            return@setMethodCallHandler
                        }
                        
                        Log.d("EasyTier", "Checking VPN permission with VpnService.prepare()")
                        val intent = VpnService.prepare(this)
                        
                        if (intent != null) {
                            Log.d("EasyTier", "VPN permission not granted, launching permission dialog")
                            pendingVpnPermissionResult = result
                            pendingVpnConfig = config
                            pendingVpnInstanceName = instanceName
                            startActivityForResult(intent, vpnPermissionRequestCode)
                            return@setMethodCallHandler
                        }

                        Log.d("EasyTier", "VPN permission already granted, starting VPN directly")
                        startVpnWithConfig(config, instanceName, result, useAndroidVpn = true)
                    }
                    
                    "checkVpnPermission" -> {
                        Log.d("EasyTier", "checkVpnPermission called")
                        val intent = VpnService.prepare(this)
                        result.success(intent == null)
                    }

                    "stopVpn" -> {
                        try {
                            stopEasyTierMonitor()
                            stopEasyTierVpnService()
                            EasyTierJNI.stopAllInstances()
                            EasyTierStateStore.clear()
                            easyTierRunningConfig = null
                            easyTierUseAndroidVpn = true
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "getNetworkInfo" -> {
                        try {
                            val info = EasyTierJNI.collectNetworkInfos(10)
                            if (!info.isNullOrBlank()) {
                                EasyTierStateStore.refreshFromJni()
                            }
                            result.success(info)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "getLastError" -> {
                        try {
                            val error = EasyTierJNI.getLastError()
                            result.success(error)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

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
        if (requestCode == manageStorageRequestCode) {
            finishPendingStoragePermissionResult()
        } else if (requestCode == vpnPermissionRequestCode) {
            finishPendingVpnPermissionResult(resultCode)
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

    private fun finishPendingVpnPermissionResult(resultCode: Int) {
        val pendingResult = pendingVpnPermissionResult ?: return
        val config = pendingVpnConfig
        val instanceName = pendingVpnInstanceName
        pendingVpnPermissionResult = null
        pendingVpnConfig = null
        pendingVpnInstanceName = null

        if (resultCode == RESULT_OK && config != null && instanceName != null) {
            Log.d("EasyTier", "VPN permission granted by user, starting VPN")
            startVpnWithConfig(config, instanceName, pendingResult, useAndroidVpn = true)
        } else {
            Log.e("EasyTier", "VPN permission denied by user, resultCode: $resultCode")
            pendingResult.error("VPN_PERMISSION_DENIED", "User denied VPN permission", null)
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

    private fun startVpnWithConfig(
        config: String,
        instanceName: String,
        result: MethodChannel.Result,
        useAndroidVpn: Boolean = true,
    ) {
        try {
            Log.d("EasyTier", "Starting EasyTier instance with config")
            val res = EasyTierJNI.runNetworkInstance(config)
            if (res == 0) {
                easyTierRunningConfig = config
                startEasyTierMonitor(instanceName)
                easyTierUseAndroidVpn = useAndroidVpn
                EasyTierStateStore.markStarted(instanceName)
                Log.d("EasyTier", "EasyTier instance started successfully useAndroidVpn=$useAndroidVpn")
                result.success(true)
            } else {
                val error = EasyTierJNI.getLastError()
                Log.e("EasyTier", "VPN start failed: $error")
                result.error("START_FAILED", error ?: "VPN start failed", null)
            }
        } catch (e: Exception) {
            Log.e("EasyTier", "Exception starting VPN: ${e.message}")
            result.error("EXCEPTION", e.message, null)
        }
    }

    private fun startEasyTierMonitor(instanceName: String) {
        stopEasyTierMonitor()
        easyTierRunningInstanceName = instanceName
        easyTierCurrentIpv4 = null
        easyTierMonitorTick = 0
        easyTierMissingInfoTicks = 0
        easyTierNotRunningTicks = 0
        easyTierRestartInProgress = false

        easyTierMonitorRunnable = object : Runnable {
            override fun run() {
                try {
                    monitorEasyTierStatus()
                } finally {
                    easyTierMonitorHandler.postDelayed(this, 3000)
                }
            }
        }

        easyTierMonitorRunnable?.let { easyTierMonitorHandler.post(it) }
    }

    private fun stopEasyTierMonitor() {
        easyTierMonitorRunnable?.let { easyTierMonitorHandler.removeCallbacks(it) }
        easyTierMonitorRunnable = null
        easyTierRunningInstanceName = null
        easyTierCurrentIpv4 = null
        easyTierMonitorTick = 0
        easyTierMissingInfoTicks = 0
        easyTierNotRunningTicks = 0
        easyTierRestartInProgress = false
        easyTierUseAndroidVpn = true
        EasyTierStateStore.clear()
    }

    private fun monitorEasyTierStatus() {
        val instanceName = easyTierRunningInstanceName ?: return
        easyTierMonitorTick += 1
        val infosJson = EasyTierJNI.collectNetworkInfos(10)
        if (infosJson.isNullOrBlank()) {
            easyTierMissingInfoTicks += 1
            Log.d("EasyTier", "No network info returned yet count=$easyTierMissingInfoTicks")
            if (easyTierMissingInfoTicks >= 4) {
                restartEasyTierInstance("missing-network-info")
            }
            return
        }
        easyTierMissingInfoTicks = 0

        try {
            val root = JSONObject(infosJson)
            val map = root.optJSONObject("map") ?: return
            val networkInfo = map.optJSONObject(instanceName) ?: return
            EasyTierStateStore.updateFromNetworkInfo(
                instanceName,
                infosJson,
                extractVirtualIpv4(networkInfo),
                networkInfo.optBoolean("running", false),
            )
            val peerCount = networkInfo.optJSONArray("peers")?.length() ?: 0
            val routeCount = networkInfo.optJSONArray("routes")?.length() ?: 0
            val myNodeInfo = networkInfo.optJSONObject("my_node_info")
            val hostname = myNodeInfo?.optString("hostname")
            val errorMsg = networkInfo.optString("error_msg")

            Log.d(
                "EasyTier",
                "Monitor tick=$easyTierMonitorTick instance=$instanceName running=${networkInfo.optBoolean("running", false)} hostname=$hostname peers=$peerCount routes=$routeCount error=$errorMsg",
            )
            logEasyTierDiagnostics(networkInfo)

            if (!networkInfo.optBoolean("running", false)) {
                easyTierNotRunningTicks += 1
                Log.w("EasyTier", "Instance not running count=$easyTierNotRunningTicks: ${networkInfo.optString("error_msg")}")
                if (easyTierNotRunningTicks >= 2) {
                    restartEasyTierInstance("instance-not-running")
                }
                return
            }
            easyTierNotRunningTicks = 0

            val virtualIpv4 = extractVirtualIpv4(networkInfo)
            if (virtualIpv4 == null) {
                if (easyTierMonitorTick <= 3 || easyTierMonitorTick % 5 == 0) {
                    Log.d("EasyTier", "Raw network info: $networkInfo")
                }
                Log.d("EasyTier", "Instance running but virtual_ipv4 not assigned yet")
                return
            }

            if (virtualIpv4 != easyTierCurrentIpv4) {
                easyTierCurrentIpv4 = virtualIpv4
                if (easyTierUseAndroidVpn) {
                    restartEasyTierVpnService(instanceName, virtualIpv4)
                } else {
                    Log.i("EasyTier", "EasyTier no-tun mode active; skipping Android VpnService route for IPv4=$virtualIpv4")
                }
            }
        } catch (e: Exception) {
            Log.e("EasyTier", "Failed to parse network info JSON", e)
        }
    }

    private fun logEasyTierDiagnostics(networkInfo: JSONObject) {
        val myNodeInfo = networkInfo.optJSONObject("my_node_info")
        val stunInfo = myNodeInfo?.optJSONObject("stun_info")
        Log.d(
            "EasyTier",
            "Diagnostics virtualIpv4=${extractVirtualIpv4(networkInfo) ?: "null"} udpNat=${stunInfo?.optString("udp_nat_type", "-") ?: "-"} tcpNat=${stunInfo?.optString("tcp_nat_type", "-") ?: "-"}",
        )

        val peerDirectConnectionCountById = mutableMapOf<Long, Int>()
        val peers = networkInfo.optJSONArray("peers")
        if (peers != null) {
            for (i in 0 until peers.length()) {
                val peer = peers.optJSONObject(i) ?: continue
                val peerId = peer.optLong("peer_id", 0L)
                peerDirectConnectionCountById[peerId] =
                    peer.optJSONArray("directly_connected_conns")?.length() ?: 0
            }
        }

        val routes = networkInfo.optJSONArray("routes")
        if (routes != null) {
            for (i in 0 until routes.length()) {
                val route = routes.optJSONObject(i) ?: continue
                val peerId = route.optLong("peer_id", 0L)
                val nextHopPeerId = route.optLong("next_hop_peer_id", 0L)
                val cost = route.optInt("cost", -1)
                val latency = route.optLong("path_latency", -1L)
                val hostname = route.optString("hostname", "")
                val featureFlag = route.optJSONObject("feature_flag")
                val publicServer = featureFlag?.optBoolean("is_public_server", false) ?: false
                val directConnectionCount = peerDirectConnectionCountById[peerId] ?: 0
                val mode = describeEasyTierRouteMode(
                    cost,
                    peerId,
                    nextHopPeerId,
                    publicServer,
                    directConnectionCount,
                )
                Log.d(
                    "EasyTier",
                    "Route[$i] host=$hostname peer=$peerId nextHop=$nextHopPeerId cost=$cost latency=${latency}ms directConns=$directConnectionCount public=$publicServer mode=$mode",
                )
            }
        }

        val events = networkInfo.optJSONArray("events")
        if (events != null && events.length() > 0) {
            val start = maxOf(0, events.length() - 3)
            for (i in start until events.length()) {
                Log.d("EasyTier", "RecentEvent[$i]=${events.optString(i)}")
            }
        }
    }

    private fun describeEasyTierRouteMode(
        cost: Int,
        peerId: Long,
        nextHopPeerId: Long,
        publicServer: Boolean,
        directConnectionCount: Int,
    ): String {
        if (publicServer) return "public-server"
        if (cost <= 1 && directConnectionCount > 0) return "direct-lan"
        if (cost <= 1) return "p2p-direct"
        if (nextHopPeerId != 0L && nextHopPeerId != peerId) return "relay-via-$nextHopPeerId"
        return "relay"
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

    private fun restartEasyTierInstance(reason: String) {
        val config = easyTierRunningConfig
        val instanceName = easyTierRunningInstanceName
        if (config.isNullOrBlank() || instanceName.isNullOrBlank() || easyTierRestartInProgress) {
            return
        }
        easyTierRestartInProgress = true
        Log.w("EasyTier", "Restarting EasyTier instance after monitor failure: reason=$reason instance=$instanceName")
        try {
            runCatching { EasyTierJNI.stopAllInstances() }
            val res = EasyTierJNI.runNetworkInstance(config)
            if (res == 0) {
                easyTierCurrentIpv4 = null
                easyTierMissingInfoTicks = 0
                easyTierNotRunningTicks = 0
                Log.i("EasyTier", "EasyTier instance restarted: reason=$reason")
            } else {
                val error = EasyTierJNI.getLastError()
                Log.e("EasyTier", "EasyTier instance restart failed: reason=$reason error=$error")
            }
        } catch (e: Exception) {
            Log.e("EasyTier", "Exception restarting EasyTier instance: reason=$reason", e)
        } finally {
            easyTierRestartInProgress = false
        }
    }

    private fun restartEasyTierVpnService(instanceName: String, ipv4: String) {
        if (!easyTierUseAndroidVpn) {
            Log.w("EasyTier", "Ignoring EasyTierVpnService start request while no-tun mode is active")
            return
        }

        val stopIntent = Intent(this, EasyTierVpnService::class.java)
        stopService(stopIntent)

        val startIntent = Intent(this, EasyTierVpnService::class.java).apply {
            putExtra("ipv4_address", ipv4)
            putExtra("instance_name", instanceName)
        }

        startService(startIntent)
        Log.i("EasyTier", "Started EasyTierVpnService with IPv4=$ipv4 routes=virtual-subnet-only")
    }

    private fun stopEasyTierVpnService() {
        val intent = Intent(this, EasyTierVpnService::class.java).apply {
            action = EasyTierVpnService.ACTION_STOP
        }
        startService(intent)
        stopService(Intent(this, EasyTierVpnService::class.java))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == readStorageRequestCode) {
            finishPendingStoragePermissionResult()
        }
    }

    private fun hasFileAccessPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            val readGranted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE,
            ) == PackageManager.PERMISSION_GRANTED
            val writeGranted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) == PackageManager.PERMISSION_GRANTED
            readGranted && writeGranted
        }
    }

    private fun requestFileAccessPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivityForResult(intent, manageStorageRequestCode)
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ),
                readStorageRequestCode,
            )
        }
    }

    private fun finishPendingStoragePermissionResult() {
        val pendingResult = pendingStoragePermissionResult ?: return
        pendingStoragePermissionResult = null
        pendingResult.success(hasFileAccessPermission())
    }

    override fun onDestroy() {
        shutdownRemoteControlResources()
        shutdownEasyTierVpnResources()
        super.onDestroy()
    }
}
