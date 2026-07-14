package lightly.tool

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class FloatingVideoChannelHandler(
    private val activity: Activity,
) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    result.success(Settings.canDrawOverlays(activity))
                }

                "requestPermission" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${activity.packageName}"),
                    )
                    activity.startActivity(intent)
                    result.success(true)
                }

                "show" -> {
                    val videoUrl = call.argument<String>("videoUrl")
                    val title = call.argument<String>("title") ?: "视频播放"
                    if (videoUrl == null) {
                        result.error("INVALID_ARGUMENTS", "videoUrl is required", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(activity, FloatingVideoService::class.java).apply {
                        putExtra("videoUrl", videoUrl)
                        putExtra("title", title)
                    }
                    activity.startService(intent)
                    result.success(true)
                }

                "close" -> {
                    activity.stopService(Intent(activity, FloatingVideoService::class.java))
                    result.success(true)
                }

                "keepScreenOn" -> {
                    val keepOn = call.argument<Boolean>("keepOn") ?: false
                    activity.runOnUiThread {
                        if (keepOn) {
                            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "floating_video"
    }
}
