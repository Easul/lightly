package lightly.tool

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class TranslationOverlayChannelHandler(private val activity: Activity) {
    private val historyStore = TranslationHistoryStore(activity)

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
                    val config = call.arguments as? Map<String, Any?> ?: emptyMap()
                    TranslationOverlayService.start(activity, config)
                    result.success(true)
                }
                "close" -> {
                    activity.stopService(Intent(activity, TranslationOverlayService::class.java))
                    result.success(true)
                }
                "isRunning" -> result.success(TranslationOverlayService.isRunning)
                "listHistory" -> result.success(historyStore.list())
                "saveHistory" -> {
                    val entry = call.arguments as? Map<String, Any?>
                    if (entry == null) result.error("INVALID", "Missing history entry", null)
                    else {
                        historyStore.save(entry)
                        result.success(true)
                    }
                }
                "updateHistory" -> {
                    val entry = call.arguments as? Map<String, Any?>
                    if (entry == null) result.error("INVALID", "Missing history entry", null)
                    else {
                        historyStore.update(entry)
                        result.success(true)
                    }
                }
                "deleteHistory" -> {
                    val arguments = call.arguments as? Map<*, *>
                    historyStore.delete(arguments?.get("id")?.toString().orEmpty())
                    result.success(true)
                }
                "clearHistory" -> {
                    historyStore.clear()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "translation_overlay"
    }
}
