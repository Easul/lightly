package lightly.tool

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class OptionalPluginChannelHandler internal constructor(
    private val platform: OptionalPluginPlatform,
) {
    constructor(activity: Activity) : this(AndroidOptionalPluginPlatform(activity))

    fun register(messenger: BinaryMessenger): MethodChannel {
        return MethodChannel(messenger, CHANNEL_NAME).also { channel ->
            channel.setMethodCallHandler(::handle)
        }
    }

    internal fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_GET_SUPPORTED_ABI -> result.success(platform.getSupportedAbi())
            METHOD_GET_PLUGIN_STATUS -> getPluginStatus(call, result)
            METHOD_CAN_REQUEST_INSTALLS -> result.success(platform.canRequestPackageInstalls())
            METHOD_OPEN_INSTALL_SETTINGS -> {
                platform.openInstallPermissionSettings()
                result.success(null)
            }
            METHOD_INSTALL_PLUGIN_APK -> installPluginApk(call, result)
            METHOD_LAUNCH_PLUGIN -> launchPlugin(call, result)
            else -> result.notImplemented()
        }
    }

    private fun getPluginStatus(call: MethodCall, result: MethodChannel.Result) {
        val packageName = call.argument<String>(ARG_PACKAGE_NAME)
        if (packageName.isNullOrBlank()) {
            result.error(ERROR_INVALID_ARGUMENTS, "Package name is required", null)
            return
        }
        result.success(platform.getPluginStatus(packageName))
    }

    private fun installPluginApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>(ARG_PATH)
        val expectedPackageName = call.argument<String>(ARG_EXPECTED_PACKAGE_NAME)
        if (path.isNullOrBlank() || expectedPackageName.isNullOrBlank()) {
            result.error(
                ERROR_INVALID_ARGUMENTS,
                "APK path and expected package name are required",
                null,
            )
            return
        }
        result.success(platform.installPluginApk(path, expectedPackageName).wireValue)
    }

    private fun launchPlugin(call: MethodCall, result: MethodChannel.Result) {
        val packageName = call.argument<String>(ARG_PACKAGE_NAME)
        if (packageName.isNullOrBlank()) {
            result.error(ERROR_INVALID_ARGUMENTS, "Package name is required", null)
            return
        }
        val extras = call.argument<Map<String, Any?>>(ARG_EXTRAS) ?: emptyMap()
        result.success(platform.launchPlugin(packageName, extras))
    }

    companion object {
        const val CHANNEL_NAME = "optional_plugins"

        private const val METHOD_GET_SUPPORTED_ABI = "getSupportedAbi"
        private const val METHOD_GET_PLUGIN_STATUS = "getPluginStatus"
        private const val METHOD_CAN_REQUEST_INSTALLS = "canRequestPackageInstalls"
        private const val METHOD_OPEN_INSTALL_SETTINGS = "openInstallPermissionSettings"
        private const val METHOD_INSTALL_PLUGIN_APK = "installPluginApk"
        private const val METHOD_LAUNCH_PLUGIN = "launchPlugin"
        private const val ARG_PACKAGE_NAME = "packageName"
        private const val ARG_PATH = "path"
        private const val ARG_EXPECTED_PACKAGE_NAME = "expectedPackageName"
        private const val ARG_EXTRAS = "extras"
        private const val ERROR_INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
    }
}

internal enum class PluginInstallResult(val wireValue: String) {
    STARTED("started"),
    PERMISSION_REQUIRED("permission_required"),
    INVALID_PACKAGE("invalid_package"),
    SIGNATURE_MISMATCH("signature_mismatch"),
    FILE_MISSING("file_missing"),
    REJECTED("rejected"),
}

internal interface OptionalPluginPlatform {
    fun getSupportedAbi(): String?
    fun getPluginStatus(packageName: String): Map<String, Any?>
    fun canRequestPackageInstalls(): Boolean
    fun openInstallPermissionSettings()
    fun installPluginApk(path: String, expectedPackageName: String): PluginInstallResult
    fun launchPlugin(packageName: String, extras: Map<String, Any?>): Boolean
}

private class AndroidOptionalPluginPlatform(
    private val activity: Activity,
) : OptionalPluginPlatform {
    private val packageManager: PackageManager = activity.packageManager

    override fun getSupportedAbi(): String? {
        return Build.SUPPORTED_ABIS.firstOrNull {
            it == "arm64-v8a" || it == "armeabi-v7a"
        }
    }

    override fun getPluginStatus(packageName: String): Map<String, Any?> {
        val packageInfo = try {
            getPackageInfo(packageName)
        } catch (_: PackageManager.NameNotFoundException) {
            return mapOf(
                "installed" to false,
                "trusted" to false,
                "enabled" to false,
            )
        }
        val applicationInfo = packageInfo.applicationInfo
        return mapOf(
            "installed" to true,
            "trusted" to signaturesMatch(packageInfo, getPackageInfo(activity.packageName)),
            "enabled" to (applicationInfo?.enabled != false),
            "versionCode" to versionCode(packageInfo),
            "versionName" to packageInfo.versionName,
            "apiVersion" to applicationInfo?.metaData?.getInt(META_API_VERSION, 0),
            "featureId" to applicationInfo?.metaData?.getString(META_FEATURE_ID),
        )
    }

    override fun canRequestPackageInstalls(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
    }

    override fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        activity.startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:${activity.packageName}")
            },
        )
    }

    override fun installPluginApk(
        path: String,
        expectedPackageName: String,
    ): PluginInstallResult {
        if (!canRequestPackageInstalls()) {
            return PluginInstallResult.PERMISSION_REQUIRED
        }
        val apk = File(path)
        val allowedRoot = File(activity.cacheDir, PLUGIN_CACHE_DIRECTORY)
        val isAllowed = try {
            apk.canonicalPath.startsWith(allowedRoot.canonicalPath + File.separator)
        } catch (_: Exception) {
            false
        }
        if (!apk.isFile || !isAllowed) {
            return PluginInstallResult.FILE_MISSING
        }
        val archiveInfo = packageManager.getPackageArchiveInfo(
            apk.absolutePath,
            packageInfoFlags(),
        ) ?: return PluginInstallResult.INVALID_PACKAGE
        if (archiveInfo.packageName != expectedPackageName) {
            return PluginInstallResult.INVALID_PACKAGE
        }
        val ownInfo = getPackageInfo(activity.packageName)
        if (!signaturesMatch(archiveInfo, ownInfo)) {
            return PluginInstallResult.SIGNATURE_MISMATCH
        }
        val uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.optional_plugins.files",
            apk,
        )
        return try {
            activity.startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, APK_MIME_TYPE)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )
            PluginInstallResult.STARTED
        } catch (_: Exception) {
            PluginInstallResult.REJECTED
        }
    }

    override fun launchPlugin(packageName: String, extras: Map<String, Any?>): Boolean {
        val pluginInfo = try {
            getPackageInfo(packageName)
        } catch (_: PackageManager.NameNotFoundException) {
            return false
        }
        if (!signaturesMatch(pluginInfo, getPackageInfo(activity.packageName))) {
            return false
        }
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        extras.forEach { (key, value) ->
            when (value) {
                is String -> intent.putExtra(key, value)
                is Int -> intent.putExtra(key, value)
                is Long -> intent.putExtra(key, value)
                is Double -> intent.putExtra(key, value)
                is Boolean -> intent.putExtra(key, value)
            }
        }
        intent.putExtra(EXTRA_HOST_PACKAGE, activity.packageName)
        intent.putExtra(
            EXTRA_HOST_DATA_AUTHORITY,
            "${activity.packageName}.optional_plugins.data",
        )
        return try {
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun getPackageInfo(packageName: String): PackageInfo {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(packageInfoFlags().toLong()),
            )
        } else {
            packageManager.getPackageInfo(packageName, packageInfoFlags())
        }
    }

    private fun packageInfoFlags(): Int {
        val signatureFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        return PackageManager.GET_META_DATA or signatureFlag
    }

    private fun signaturesMatch(left: PackageInfo, right: PackageInfo): Boolean {
        val leftDigests = signingCertificateDigests(left)
        val rightDigests = signingCertificateDigests(right)
        return leftDigests.isNotEmpty() && leftDigests.any(rightDigests::contains)
    }

    @Suppress("DEPRECATION")
    private fun signingCertificateDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return emptySet()
            if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
        } else {
            info.signatures ?: emptyArray()
        }
        return signatures.mapTo(mutableSetOf()) { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
        }
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
    }

    companion object {
        private const val PLUGIN_CACHE_DIRECTORY = "optional_plugins"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val META_API_VERSION = "lightly.plugin.API_VERSION"
        private const val META_FEATURE_ID = "lightly.plugin.FEATURE_ID"
        private const val EXTRA_HOST_PACKAGE = "lightly.host.PACKAGE"
        private const val EXTRA_HOST_DATA_AUTHORITY = "lightly.host.DATA_AUTHORITY"
    }
}
