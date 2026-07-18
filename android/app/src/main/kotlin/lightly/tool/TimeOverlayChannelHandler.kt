package lightly.tool

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class TimeOverlayChannelHandler(private val activity: Activity) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> result.success(Settings.canDrawOverlays(activity))
                "requestPermission" -> {
                    activity.startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:${activity.packageName}"),
                        ),
                    )
                    result.success(true)
                }
                "show" -> {
                    TimeOverlayService.start(activity)
                    result.success(true)
                }
                "close" -> {
                    activity.stopService(Intent(activity, TimeOverlayService::class.java))
                    result.success(true)
                }
                "isRunning" -> result.success(TimeOverlayService.isRunning)
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "time_overlay"
    }
}
