package lightly.tool

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.InvocationTargetException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal interface YouTubeResolverRuntime {
    fun apiVersion(): Int?

    fun resolve(url: String, proxyRoute: String): String
}

internal class ReflectionYouTubeResolverRuntime(
    private val context: Context,
) : YouTubeResolverRuntime {
    override fun apiVersion(): Int? = runCatching {
        bridgeClass.getMethod("apiVersion").invoke(null) as? Int
    }.getOrNull()

    override fun resolve(url: String, proxyRoute: String): String {
        try {
            return bridgeClass
                .getMethod(
                    "resolve",
                    Context::class.java,
                    String::class.java,
                    String::class.java,
                )
                .invoke(null, context, url, proxyRoute) as String
        } catch (error: InvocationTargetException) {
            throw error.targetException ?: error
        }
    }

    private val bridgeClass: Class<*>
        get() = Class.forName(BRIDGE_CLASS_NAME)

    companion object {
        private const val BRIDGE_CLASS_NAME =
            "lightly.youtube.resolver.YouTubeResolverBridge"
    }
}

internal class YouTubeResolverChannelHandler(
    private val runtime: YouTubeResolverRuntime,
    private val executor: ExecutorService = Executors.newSingleThreadExecutor(),
) {
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(::handle)
    }

    internal fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> {
                val apiVersion = runtime.apiVersion()
                result.success(
                    mapOf(
                        "available" to (apiVersion != null && apiVersion >= MIN_API_VERSION),
                        "apiVersion" to apiVersion,
                    ),
                )
            }

            "resolve" -> resolve(call, result)
            else -> result.notImplemented()
        }
    }

    private fun resolve(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim().orEmpty()
        val proxyRoute = call.argument<String>("proxyRoute")?.trim().orEmpty()
        if (url.isEmpty()) {
            result.error("INVALID_ARGUMENTS", "url is required", null)
            return
        }
        val apiVersion = runtime.apiVersion()
        if (apiVersion == null || apiVersion < MIN_API_VERSION) {
            result.error("UNAVAILABLE", "当前安装包未包含 YouTube 解析组件", null)
            return
        }

        executor.execute {
            runCatching {
                runtime.resolve(url, proxyRoute)
            }.fold(
                onSuccess = { payload ->
                    mainHandler.post { result.success(payload) }
                },
                onFailure = { error ->
                    val message = error.message
                        ?.takeIf { it.isNotBlank() }
                        ?: "YouTube 解析失败"
                    mainHandler.post {
                        result.error("RESOLVE_FAILED", message, null)
                    }
                },
            )
        }
    }

    fun shutdown() {
        executor.shutdownNow()
    }

    companion object {
        const val CHANNEL_NAME = "youtube_resolver"
        const val MIN_API_VERSION = 1
    }
}
