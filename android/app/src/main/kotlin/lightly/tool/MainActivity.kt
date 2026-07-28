package lightly.tool

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var browserProxyChannel: MethodChannel? = null
    private val storageAccessChannelHandler by lazy { StorageAccessChannelHandler(this) }
    private val externalIntentChannelHandler by lazy { ExternalIntentChannelHandler(this) }
    private val proxyFloatingModeChannelHandler by lazy {
        ProxyFloatingModeChannelHandler(this)
    }
    private val optionalPluginActivationCoordinator by lazy {
        OptionalPluginActivationCoordinator(this)
    }
    private val easyTierChannelHandler by lazy {
        EasyTierChannelHandler(this, optionalPluginActivationCoordinator)
    }
    private val telegramPluginChannelHandler by lazy {
        TelegramPluginChannelHandler(this, optionalPluginActivationCoordinator)
    }
    private val webRtcVoicePluginChannelHandler by lazy {
        WebRtcVoicePluginChannelHandler(this, optionalPluginActivationCoordinator)
    }
    private var remoteControlChannelHandler: RemoteControlChannelHandler? = null

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

    private val logTag = "BrowserProxy"
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun shutdownRemoteControlResources() {
        remoteControlChannelHandler?.shutdown()
        remoteControlChannelHandler = null
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
        OptionalPluginChannelHandler(this)
            .register(flutterEngine.dartExecutor.binaryMessenger)
        telegramPluginChannelHandler.register(flutterEngine.dartExecutor.binaryMessenger)
        webRtcVoicePluginChannelHandler.register(flutterEngine.dartExecutor.binaryMessenger)

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

        remoteControlChannelHandler = RemoteControlChannelHandler(
            this,
            flutterEngine.renderer,
        ).also { handler ->
            handler.register(flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (storageAccessChannelHandler.handlePermissionResult(requestCode)) {
            return
        } else if (optionalPluginActivationCoordinator.handleActivityResult(requestCode, resultCode)) {
            return
        } else if (webRtcVoicePluginChannelHandler.handleActivityResult(requestCode, resultCode)) {
            return
        } else if (easyTierChannelHandler.handleActivityResult(requestCode, resultCode)) {
            return
        } else if (
            remoteControlChannelHandler?.handleActivityResult(
                requestCode,
                resultCode,
                data,
            ) == true
        ) {
            return
        }
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
        optionalPluginActivationCoordinator.clear()
        telegramPluginChannelHandler.shutdown()
        webRtcVoicePluginChannelHandler.shutdown()
        shutdownRemoteControlResources()
        shutdownEasyTierVpnResources()
        super.onDestroy()
    }
}
