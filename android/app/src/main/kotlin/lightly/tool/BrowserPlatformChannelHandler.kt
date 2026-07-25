package lightly.tool

import android.os.Handler
import android.os.Looper
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

class BrowserPlatformChannelHandler internal constructor(
    private val proxyOverride: BrowserProxyOverride = AndroidBrowserProxyOverride(),
    private val methodHandlers: List<BrowserPlatformMethodHandler> = emptyList(),
) {
    fun register(messenger: BinaryMessenger): MethodChannel {
        return MethodChannel(messenger, CHANNEL_NAME).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (!handle(call, result)) {
                    result.notImplemented()
                }
            }
        }
    }

    internal fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            METHOD_IS_SUPPORTED -> result.success(proxyOverride.isSupported())
            METHOD_SET_PROXY -> setProxy(call, result)
            METHOD_CLEAR_PROXY -> clearProxy(result)
            else -> return methodHandlers.any { it.handle(call, result) }
        }
        return true
    }

    private fun setProxy(call: MethodCall, result: MethodChannel.Result) {
        if (!proxyOverride.isSupported()) {
            result.error(ERROR_UNSUPPORTED, "WebView proxy override is not supported", null)
            return
        }

        val host = call.argument<String>(ARG_HOST)
        val port = call.argument<Int>(ARG_PORT)
        if (host.isNullOrBlank() || port == null) {
            result.error(ERROR_INVALID_ARGUMENTS, "Host and port are required", null)
            return
        }

        proxyOverride.setProxy(
            host = host,
            port = port,
            scheme = call.argument<String>(ARG_SCHEME) ?: DEFAULT_SCHEME,
            bypassDomains = call.argument<List<String>>(ARG_BYPASS_DOMAINS) ?: emptyList(),
        ) {
            result.success(true)
        }
    }

    private fun clearProxy(result: MethodChannel.Result) {
        if (!proxyOverride.isSupported()) {
            result.success(false)
            return
        }

        proxyOverride.clearProxy {
            result.success(true)
        }
    }

    companion object {
        const val CHANNEL_NAME = "browser_proxy"

        private const val METHOD_IS_SUPPORTED = "isSupported"
        private const val METHOD_SET_PROXY = "setProxy"
        private const val METHOD_CLEAR_PROXY = "clearProxy"
        private const val ARG_HOST = "host"
        private const val ARG_PORT = "port"
        private const val ARG_SCHEME = "scheme"
        private const val ARG_BYPASS_DOMAINS = "bypassDomains"
        private const val DEFAULT_SCHEME = "http"
        private const val ERROR_UNSUPPORTED = "UNSUPPORTED"
        private const val ERROR_INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
    }
}

internal fun interface BrowserPlatformMethodHandler {
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean
}

internal interface BrowserProxyOverride {
    fun isSupported(): Boolean

    fun setProxy(
        host: String,
        port: Int,
        scheme: String,
        bypassDomains: List<String>,
        onComplete: () -> Unit,
    )

    fun clearProxy(onComplete: () -> Unit)
}

private class AndroidBrowserProxyOverride : BrowserProxyOverride {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executor { runnable ->
        if (Looper.myLooper() == Looper.getMainLooper()) {
            runnable.run()
        } else {
            mainHandler.post(runnable)
        }
    }

    override fun isSupported(): Boolean {
        return WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)
    }

    override fun setProxy(
        host: String,
        port: Int,
        scheme: String,
        bypassDomains: List<String>,
        onComplete: () -> Unit,
    ) {
        val proxyConfigBuilder = ProxyConfig.Builder()
            .addProxyRule("${scheme.lowercase()}://$host:$port")
            .addDirect()
            .addBypassRule("localhost")
            .addBypassRule("127.0.0.1")
            .addBypassRule("127.*")
            .addBypassRule("::1")

        bypassDomains
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }
            .forEach(proxyConfigBuilder::addBypassRule)

        ProxyController.getInstance().setProxyOverride(
            proxyConfigBuilder.build(),
            executor,
            onComplete,
        )
    }

    override fun clearProxy(onComplete: () -> Unit) {
        ProxyController.getInstance().clearProxyOverride(executor, onComplete)
    }
}
