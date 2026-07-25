package lightly.tool

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ProxyFloatingModeChannelHandler(
    private val activity: Activity,
) : BrowserPlatformMethodHandler {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            METHOD_START -> start(result)
            METHOD_STOP -> {
                stop()
                result.success(true)
            }
            else -> return false
        }
        return true
    }

    fun stop() {
        runCatching {
            activity.stopService(Intent(activity, ProxyFloatingButtonService::class.java))
        }
    }

    private fun start(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(activity)
        ) {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
            result.success(RESULT_PERMISSION_REQUIRED)
            return
        }
        ContextCompat.startForegroundService(
            activity,
            Intent(activity, ProxyFloatingButtonService::class.java),
        )
        activity.moveTaskToBack(true)
        result.success(RESULT_STARTED)
    }

    companion object {
        private const val METHOD_START = "startProxyFloatingButtonMode"
        private const val METHOD_STOP = "stopProxyFloatingButtonMode"
        private const val RESULT_PERMISSION_REQUIRED = "permission_required"
        private const val RESULT_STARTED = "started"
    }
}
