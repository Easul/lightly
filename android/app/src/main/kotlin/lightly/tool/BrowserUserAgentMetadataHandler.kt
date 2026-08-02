package lightly.tool

import android.view.WindowInsets
import androidx.webkit.UserAgentMetadata
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature
import com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class BrowserUserAgentMetadataHandler(
    private val metadataRuntime: BrowserUserAgentMetadataRuntime,
) : BrowserPlatformMethodHandler {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != METHOD_PREPARE_WEB_VIEW) {
            return false
        }
        val webViewId = call.argument<Any>(ARG_WEB_VIEW_ID)?.toString()
        val desktopUserAgent = call.argument<String>(ARG_DESKTOP_USER_AGENT)?.trim()
        if (webViewId.isNullOrEmpty()) {
            result.error(ERROR_INVALID_ARGUMENTS, "WebView id is required", null)
            return true
        }
        result.success(metadataRuntime.prepareWebView(webViewId, desktopUserAgent))
        return true
    }

    private companion object {
        const val METHOD_PREPARE_WEB_VIEW = "prepareBrowserWebView"
        const val ARG_WEB_VIEW_ID = "webViewId"
        const val ARG_DESKTOP_USER_AGENT = "desktopUserAgent"
        const val ERROR_INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
    }
}

internal fun interface BrowserUserAgentMetadataRuntime {
    fun prepareWebView(webViewId: String, desktopUserAgent: String?): Boolean
}

internal class AndroidBrowserUserAgentMetadataRuntime(
    private val plugin: InAppWebViewFlutterPlugin?,
) : BrowserUserAgentMetadataRuntime {
    override fun prepareWebView(webViewId: String, desktopUserAgent: String?): Boolean {
        val webView = plugin?.inAppWebViewManager
            ?.keepAliveWebViews
            ?.get(webViewId)
            ?.webView
            ?: return false

        consumeDuplicateNavigationBarInset(webView)
        if (desktopUserAgent.isNullOrEmpty() ||
            !WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA)
        ) {
            return true
        }
        return try {
            val current = WebSettingsCompat.getUserAgentMetadata(webView.settings)
            val platform = desktopPlatformForUserAgent(desktopUserAgent)
            val metadata = UserAgentMetadata.Builder(current)
                .setMobile(false)
                .setPlatform(platform.name)
                .setPlatformVersion(platform.version)
                .setArchitecture("x86")
                .setBitness(64)
                .setModel("")
                .setWow64(false)
                .build()
            WebSettingsCompat.setUserAgentMetadata(webView.settings, metadata)
            true
        } catch (_: RuntimeException) {
            false
        }
    }
}

private fun consumeDuplicateNavigationBarInset(webView: android.webkit.WebView) {
    webView.setOnApplyWindowInsetsListener { view, insets ->
        val adjusted = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            WindowInsets.Builder(insets)
                .setInsets(WindowInsets.Type.navigationBars(), android.graphics.Insets.NONE)
                .setInsetsIgnoringVisibility(
                    WindowInsets.Type.navigationBars(),
                    android.graphics.Insets.NONE,
                )
                .build()
        } else {
            @Suppress("DEPRECATION")
            val keyboardInset = (
                insets.systemWindowInsetBottom - insets.stableInsetBottom
            ).coerceAtLeast(0)
            @Suppress("DEPRECATION")
            insets.replaceSystemWindowInsets(
                insets.systemWindowInsetLeft,
                insets.systemWindowInsetTop,
                insets.systemWindowInsetRight,
                keyboardInset,
            )
        }
        view.onApplyWindowInsets(adjusted)
    }
    webView.requestApplyInsets()
}

internal data class DesktopUserAgentPlatform(
    val name: String,
    val version: String,
)

internal fun desktopPlatformForUserAgent(userAgent: String): DesktopUserAgentPlatform {
    return when {
        userAgent.contains("Macintosh") || userAgent.contains("Mac OS X") ->
            DesktopUserAgentPlatform("macOS", "14.0.0")
        userAgent.contains("CrOS") -> DesktopUserAgentPlatform("Chrome OS", "")
        userAgent.contains("Linux") && !userAgent.contains("Android") ->
            DesktopUserAgentPlatform("Linux", "")
        else -> DesktopUserAgentPlatform("Windows", "10.0.0")
    }
}
