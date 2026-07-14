package lightly.tool

import android.content.Context
import android.media.MediaScannerConnection
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MediaScannerChannelHandler(
    private val context: Context,
) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> scanFile(call.argument("filePath"), result)
                "scanDirectory" -> scanDirectory(call.argument("directoryPath"), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun scanFile(filePath: String?, result: MethodChannel.Result) {
        if (filePath.isNullOrEmpty()) {
            result.error("INVALID_PATH", "File path is required", null)
            return
        }
        try {
            val file = File(filePath)
            if (!file.exists()) {
                result.success(false)
                return
            }
            MediaScannerConnection.scanFile(
                context,
                arrayOf(filePath),
                null,
            ) { _, _ -> }
            result.success(true)
        } catch (error: Exception) {
            result.error("SCAN_FAILED", error.message, null)
        }
    }

    private fun scanDirectory(directoryPath: String?, result: MethodChannel.Result) {
        if (directoryPath.isNullOrEmpty()) {
            result.error("INVALID_PATH", "Directory path is required", null)
            return
        }
        try {
            val directory = File(directoryPath)
            if (!directory.exists() || !directory.isDirectory) {
                result.success(false)
                return
            }
            val files = directory.listFiles()?.map { it.absolutePath }?.toTypedArray()
            if (!files.isNullOrEmpty()) {
                MediaScannerConnection.scanFile(context, files, null) { _, _ -> }
            }
            result.success(true)
        } catch (error: Exception) {
            result.error("SCAN_FAILED", error.message, null)
        }
    }

    companion object {
        const val CHANNEL_NAME = "media_scanner"
    }
}
