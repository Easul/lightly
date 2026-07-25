package lightly.tool

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class StorageAccessChannelHandler internal constructor(
    private val platform: StorageAccessPlatform,
) : BrowserPlatformMethodHandler {
    constructor(activity: Activity) : this(AndroidStorageAccessPlatform(activity))

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            METHOD_GET_SHARED_DOWNLOADS_PATH -> {
                result.success(platform.getSharedDownloadsPath())
            }

            METHOD_HAS_FILE_ACCESS_PERMISSION -> {
                result.success(platform.hasFileAccessPermission())
            }

            METHOD_REQUEST_FILE_ACCESS_PERMISSION -> requestPermission(result)
            else -> return false
        }
        return true
    }

    fun handlePermissionResult(requestCode: Int): Boolean {
        if (requestCode != MANAGE_STORAGE_REQUEST_CODE &&
            requestCode != READ_STORAGE_REQUEST_CODE
        ) {
            return false
        }
        finishPendingPermissionResult()
        return true
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (pendingPermissionResult != null) {
            result.error(
                ERROR_IN_PROGRESS,
                "Storage permission request already in progress",
                null,
            )
            return
        }
        if (platform.hasFileAccessPermission()) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        platform.requestFileAccessPermission(
            manageStorageRequestCode = MANAGE_STORAGE_REQUEST_CODE,
            readStorageRequestCode = READ_STORAGE_REQUEST_CODE,
        )
    }

    private fun finishPendingPermissionResult() {
        val pendingResult = pendingPermissionResult ?: return
        pendingPermissionResult = null
        pendingResult.success(platform.hasFileAccessPermission())
    }

    companion object {
        private const val METHOD_GET_SHARED_DOWNLOADS_PATH = "getSharedDownloadsPath"
        private const val METHOD_HAS_FILE_ACCESS_PERMISSION = "hasFileAccessPermission"
        private const val METHOD_REQUEST_FILE_ACCESS_PERMISSION =
            "requestFileAccessPermission"
        private const val ERROR_IN_PROGRESS = "IN_PROGRESS"
        private const val MANAGE_STORAGE_REQUEST_CODE = 4101
        private const val READ_STORAGE_REQUEST_CODE = 4102
    }
}

internal interface StorageAccessPlatform {
    fun getSharedDownloadsPath(): String
    fun hasFileAccessPermission(): Boolean
    fun requestFileAccessPermission(
        manageStorageRequestCode: Int,
        readStorageRequestCode: Int,
    )
}

private class AndroidStorageAccessPlatform(
    private val activity: Activity,
) : StorageAccessPlatform {
    override fun getSharedDownloadsPath(): String {
        return Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        ).absolutePath
    }

    override fun hasFileAccessPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager()
        }
        val readGranted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.READ_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
        val writeGranted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
        return readGranted && writeGranted
    }

    override fun requestFileAccessPermission(
        manageStorageRequestCode: Int,
        readStorageRequestCode: Int,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.startActivityForResult(
                Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:${activity.packageName}")
                },
                manageStorageRequestCode,
            )
            return
        }
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ),
            readStorageRequestCode,
        )
    }
}
