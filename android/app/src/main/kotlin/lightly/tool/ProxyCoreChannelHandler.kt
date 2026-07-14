package lightly.tool

import android.util.Log
import com.proxy.core.ProxyCore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class ProxyCoreChannelHandler {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "nativeInit" -> {
                    val logLevel = call.argument<String>("logLevel") ?: "info"
                    Log.i(LOG_TAG, "MethodChannel nativeInit called, logLevel=$logLevel")
                    val nativeResult = ProxyCore.nativeInit(logLevel)
                    Log.i(LOG_TAG, "nativeInit result=$nativeResult")
                    result.success(nativeResult)
                }

                "nativeStart" -> {
                    val listenAddress =
                        call.argument<String>("listenAddr") ?: "127.0.0.1:23333"
                    val config = call.argument<String>("config") ?: "{}"
                    Log.i(
                        LOG_TAG,
                        "MethodChannel nativeStart called, listenAddr=$listenAddress, configLength=${config.length}",
                    )
                    val nativeResult = ProxyCore.nativeStart(listenAddress, config)
                    Log.i(LOG_TAG, "nativeStart result=$nativeResult")
                    result.success(nativeResult)
                }

                "nativeStop" -> {
                    Log.i(LOG_TAG, "MethodChannel nativeStop called")
                    val nativeResult = ProxyCore.nativeStop()
                    Log.i(LOG_TAG, "nativeStop result=$nativeResult")
                    result.success(nativeResult)
                }

                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "com.proxy.core/proxy"
        private const val LOG_TAG = "ProxyCore"
    }
}
