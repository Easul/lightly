package lightly.tool

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
        if (call.method != METHOD_APPLY_DESKTOP_METADATA) {
            return false
        }
        val webViewId = call.argument<Any>(ARG_WEB_VIEW_ID)?.toString()
        val userAgent = call.argument<String>(ARG_USER_AGENT)?.trim()
        if (webViewId.isNullOrEmpty() || userAgent.isNullOrEmpty()) {
            result.error(ERROR_INVALID_ARGUMENTS, "WebView id and user agent are required", null)
            return true
        }
        result.success(metadataRuntime.applyDesktopMetadata(webViewId, userAgent))
        return true
    }

    private companion object {
        const val METHOD_APPLY_DESKTOP_METADATA = "applyDesktopUserAgentMetadata"
        const val ARG_WEB_VIEW_ID = "webViewId"
        const val ARG_USER_AGENT = "userAgent"
        const val ERROR_INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
    }
}

internal fun interface BrowserUserAgentMetadataRuntime {
    fun applyDesktopMetadata(webViewId: String, userAgent: String): Boolean
}

internal class AndroidBrowserUserAgentMetadataRuntime(
    private val plugin: InAppWebViewFlutterPlugin?,
) : BrowserUserAgentMetadataRuntime {
    override fun applyDesktopMetadata(webViewId: String, userAgent: String): Boolean {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA)) {
            return false
        }
        val webView = plugin?.inAppWebViewManager
            ?.keepAliveWebViews
            ?.get(webViewId)
            ?.webView
            ?: return false
        return try {
            val current = WebSettingsCompat.getUserAgentMetadata(webView.settings)
            val platform = desktopPlatformForUserAgent(userAgent)
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
