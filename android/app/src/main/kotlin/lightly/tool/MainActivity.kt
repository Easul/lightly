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
import android.provider.OpenableColumns
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
import java.io.File
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
    private var easyTierCurrentProxyCidrs: List<String> = emptyList()
    private var easyTierMonitorTick = 0
    private var easyTierRunningConfig: String? = null
    private var easyTierMissingInfoTicks = 0
    private var easyTierNotRunningTicks = 0
    private var easyTierRestartInProgress = false
    private var remoteControlService: RemoteControlService? = null

    private var initialIntentUrl: String? = null
    private var browserProxyChannel: MethodChannel? = null

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

    private fun importContentUriToPrivateFile(uriString: String): String? {
        val uri = Uri.parse(uriString)
        if (uri.scheme?.lowercase() != "content") {
            return uriString
        }

        val importsDir = resolveImportedDocumentsDir()
        if (!importsDir.exists()) {
            importsDir.mkdirs()
        }

        val displayName = queryContentDisplayName(uri)?.trim().orEmpty()
        val safeName = sanitizeImportedFileName(displayName.ifEmpty {
            "imported_${System.currentTimeMillis()}.txt"
        })
        val targetFile = buildUniqueImportedFile(importsDir, safeName)

        contentResolver.openInputStream(uri)?.use { input ->
            targetFile.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: return null

        return Uri.fromFile(targetFile).toString()
    }

    private fun resolveImportedDocumentsDir(): File {
        val externalDir = getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS)
        if (externalDir != null) {
            return File(externalDir, "imported_documents")
        }
        return File(filesDir, "imported_documents")
    }

    private fun queryContentDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (!cursor.moveToFirst()) {
                        return@use null
                    }
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index == -1) {
                        null
                    } else {
                        cursor.getString(index)
                    }
                }
        } catch (e: Exception) {
            Log.w(logTag, "Failed to query display name for $uri", e)
            null
        }
    }

    private fun sanitizeImportedFileName(rawName: String): String {
        val trimmed = rawName.trim()
        val fallback = if (trimmed.isEmpty()) {
            "imported_${System.currentTimeMillis()}.txt"
        } else {
            trimmed
        }
        return fallback.replace(Regex("[\\\\/:*?\"<>|]"), "_")
    }

    private fun buildUniqueImportedFile(parent: File, fileName: String): File {
        val dotIndex = fileName.lastIndexOf('.')
        val baseName = if (dotIndex > 0) fileName.substring(0, dotIndex) else fileName
        val extension = if (dotIndex > 0) fileName.substring(dotIndex) else ""
        var candidate = File(parent, fileName)
        var counter = 1
        while (candidate.exists()) {
            candidate = File(parent, "${baseName}_${counter}${extension}")
            counter += 1
        }
        return candidate
    }

    private fun cleanupImportedPrivateFiles(retainedUrls: List<String>): Boolean {
        val importRoots = listOf(
            File(filesDir, "imported_documents"),
            resolveImportedDocumentsDir(),
        ).map { it.canonicalFile }.distinctBy { it.path }

        val retainedFiles = retainedUrls.mapNotNull { retainedUrl ->
            try {
                val uri = Uri.parse(retainedUrl)
                if (uri.scheme?.lowercase() != "file") {
                    return@mapNotNull null
                }
                val path = uri.path ?: return@mapNotNull null
                val file = File(path).canonicalFile
                val matchingRoot = importRoots.firstOrNull { root ->
                    file.path.startsWith(root.path + File.separator)
                }
                if (matchingRoot != null) file.path else null
            } catch (_: Exception) {
                null
            }
        }.toSet()

        importRoots.forEach { importsRoot ->
            if (!importsRoot.exists()) {
                return@forEach
            }
            importsRoot.listFiles()?.forEach { child ->
                val canonicalChild = child.canonicalFile
                if (!retainedFiles.contains(canonicalChild.path)) {
                    canonicalChild.delete()
                }
            }
        }

        return true
    }

    private val channelName = "browser_proxy"
    private val floatingChannelName = "floating_video"
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, floatingChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermission" -> {
                        result.success(Settings.canDrawOverlays(this))
                    }
                    "requestPermission" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(true)
                    }
                    "show" -> {
                        val videoUrl = call.argument<String>("videoUrl")
                        val title = call.argument<String>("title") ?: "视频播放"
                        if (videoUrl != null) {
                            val intent = Intent(this, FloatingVideoService::class.java).apply {
                                putExtra("videoUrl", videoUrl)
                                putExtra("title", title)
                            }
                            startService(intent)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENTS", "videoUrl is required", null)
                        }
                    }
                    "close" -> {
                        val intent = Intent(this, FloatingVideoService::class.java)
                        stopService(intent)
                        result.success(true)
                    }
                    "keepScreenOn" -> {
                        val keepOn = call.argument<Boolean>("keepOn") ?: false
                        runOnUiThread {
                            if (keepOn) {
                                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

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
                        result.success(initialIntentUrl)
                    }

                    "importContentUriToPrivateFile" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString.isNullOrBlank()) {
                            result.error("INVALID_URI", "URI is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(importContentUriToPrivateFile(uriString))
                        } catch (e: Exception) {
                            Log.e(logTag, "Failed to import content URI: $uriString", e)
                            result.error("IMPORT_FAILED", e.message, null)
                        }
                    }

                    "cleanupImportedPrivateFiles" -> {
                        val retainedUrls =
                            call.argument<List<String>>("retainedUrls") ?: emptyList()
                        try {
                            result.success(cleanupImportedPrivateFiles(retainedUrls))
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "media_scanner")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanFile" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrEmpty()) {
                            result.error("INVALID_PATH", "File path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = java.io.File(filePath)
                            if (file.exists()) {
                                android.media.MediaScannerConnection.scanFile(
                                    this,
                                    arrayOf(filePath),
                                    null
                                ) { _, _ -> }
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("SCAN_FAILED", e.message, null)
                        }
                    }
                    "scanDirectory" -> {
                        val dirPath = call.argument<String>("directoryPath")
                        if (dirPath.isNullOrEmpty()) {
                            result.error("INVALID_PATH", "Directory path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val dir = java.io.File(dirPath)
                            if (dir.exists() && dir.isDirectory) {
                                val files = dir.listFiles()?.map { it.absolutePath }?.toTypedArray()
                                if (files != null && files.isNotEmpty()) {
                                    android.media.MediaScannerConnection.scanFile(
                                        this,
                                        files,
                                        null
                                    ) { _, _ -> }
                                }
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("SCAN_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

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
                        Log.d("EasyTier", "startVpn called with config length: ${config?.length ?: 0}")
                        
                        if (config.isNullOrBlank() || instanceName.isNullOrBlank()) {
                            Log.e("EasyTier", "Config is null or blank")
                            result.error("INVALID_CONFIG", "Config and instanceName are required", null)
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
                        startVpnWithConfig(config, instanceName, result)
                    }
                    
                    "checkVpnPermission" -> {
                        Log.d("EasyTier", "checkVpnPermission called")
                        val intent = VpnService.prepare(this)
                        result.success(intent == null)
                    }

                    "stopVpn" -> {
                        try {
                            stopEasyTierMonitor()
                            val intent = Intent(this, EasyTierVpnService::class.java).apply {
                                action = EasyTierVpnService.ACTION_STOP
                            }
                            startService(intent)
                            EasyTierJNI.stopAllInstances()
                            easyTierRunningConfig = null
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EXCEPTION", e.message, null)
                        }
                    }

                    "getNetworkInfo" -> {
                        try {
                            val info = EasyTierJNI.collectNetworkInfos(10)
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.proxy.core/proxy")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeInit" -> {
                        val logLevel = call.argument<String>("logLevel") ?: "info"
                        Log.i("ProxyCore", "MethodChannel nativeInit called, logLevel=$logLevel")
                        val res = com.proxy.core.ProxyCore.nativeInit(logLevel)
                        Log.i("ProxyCore", "nativeInit result=$res")
                        result.success(res)
                    }
                    "nativeStart" -> {
                        val listenAddr = call.argument<String>("listenAddr") ?: "127.0.0.1:23333"
                        val config = call.argument<String>("config") ?: "{}"
                        Log.i("ProxyCore", "MethodChannel nativeStart called, listenAddr=$listenAddr, configLength=${config.length}")
                        val res = com.proxy.core.ProxyCore.nativeStart(listenAddr, config)
                        Log.i("ProxyCore", "nativeStart result=$res")
                        result.success(res)
                    }
                    "nativeStop" -> {
                        Log.i("ProxyCore", "MethodChannel nativeStop called")
                        val res = com.proxy.core.ProxyCore.nativeStop()
                        Log.i("ProxyCore", "nativeStop result=$res")
                        result.success(res)
                    }
                    else -> result.notImplemented()
                }
            }

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
                            val fps = call.argument<Int>("fps") ?: 15
                            val bitrate = call.argument<Int>("bitrate") ?: 2000000
                            
                            if (remoteControlService == null) {
                                remoteControlService = RemoteControlService(this)
                            }
                            
                            pendingScreenCaptureFps = fps
                            pendingScreenCaptureBitrate = bitrate
                            
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
                            result.success(true)
                        } catch (e: Exception) {
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
            remoteControlService?.handleMediaProjectionResult(
                resultCode, data,
                pendingScreenCaptureFps,
                pendingScreenCaptureBitrate
            )
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
            startVpnWithConfig(config, instanceName, pendingResult)
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

    private fun startVpnWithConfig(config: String, instanceName: String, result: MethodChannel.Result) {
        try {
            Log.d("EasyTier", "Starting EasyTier instance with config")
            val res = EasyTierJNI.runNetworkInstance(config)
            if (res == 0) {
                easyTierRunningConfig = config
                startEasyTierMonitor(instanceName)
                Log.d("EasyTier", "VPN started successfully")
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
        easyTierCurrentProxyCidrs = emptyList()
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
        easyTierCurrentProxyCidrs = emptyList()
        easyTierMonitorTick = 0
        easyTierMissingInfoTicks = 0
        easyTierNotRunningTicks = 0
        easyTierRestartInProgress = false
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

            val proxyCidrs = extractProxyCidrs(networkInfo)
            if (virtualIpv4 != easyTierCurrentIpv4 || proxyCidrs != easyTierCurrentProxyCidrs) {
                easyTierCurrentIpv4 = virtualIpv4
                easyTierCurrentProxyCidrs = proxyCidrs
                restartEasyTierVpnService(instanceName, virtualIpv4, proxyCidrs)
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

    private fun extractProxyCidrs(networkInfo: JSONObject): List<String> {
        val routes = networkInfo.optJSONArray("routes") ?: return emptyList()
        val proxyCidrs = mutableListOf<String>()
        for (i in 0 until routes.length()) {
            val route = routes.optJSONObject(i) ?: continue
            val cidrs = route.optJSONArray("proxy_cidrs") ?: continue
            for (j in 0 until cidrs.length()) {
                val cidr = cidrs.optString(j)
                if (cidr.isNotBlank()) {
                    proxyCidrs.add(cidr)
                }
            }
        }
        return proxyCidrs
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
                easyTierCurrentProxyCidrs = emptyList()
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

    private fun restartEasyTierVpnService(instanceName: String, ipv4: String, proxyCidrs: List<String>) {
        val stopIntent = Intent(this, EasyTierVpnService::class.java)
        stopService(stopIntent)

        val startIntent = Intent(this, EasyTierVpnService::class.java).apply {
            putExtra("ipv4_address", ipv4)
            putStringArrayListExtra("proxy_cidrs", ArrayList(proxyCidrs))
            putExtra("instance_name", instanceName)
        }

        startService(startIntent)
        Log.i("EasyTier", "Started EasyTierVpnService with IPv4=$ipv4 proxyCidrs=$proxyCidrs")
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
