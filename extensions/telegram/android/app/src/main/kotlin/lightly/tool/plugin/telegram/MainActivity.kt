package lightly.tool.plugin.telegram

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var proxyPort: Int? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        captureHostIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler(::handleMethodCall)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (captureHostIntent(intent)) {
            channel?.invokeMethod(METHOD_HOST_CONTEXT_CHANGED, hostContext())
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                METHOD_GET_HOST_CONTEXT -> result.success(hostContext())
                METHOD_READ_TELEGRAM_CONFIG -> result.success(readTelegramConfig())
                METHOD_WRITE_TELEGRAM_CONFIG -> {
                    val json = call.argument<String>(ARG_JSON)
                    if (json == null) {
                        result.error(ERROR_INVALID_ARGUMENTS, "Telegram config is required", null)
                    } else {
                        result.success(writeTelegramConfig(json))
                    }
                }
                else -> result.notImplemented()
            }
        } catch (error: SecurityException) {
            result.error(ERROR_HOST_ACCESS_DENIED, "Lightly rejected plugin access", null)
        } catch (error: Exception) {
            result.error(ERROR_HOST_UNAVAILABLE, "Lightly plugin data is unavailable", null)
        }
    }

    private fun readTelegramConfig(): String? {
        val uri = telegramConfigUri()
        return contentResolver.query(
            uri,
            arrayOf(COLUMN_JSON),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) {
                return@use null
            }
            val columnIndex = cursor.getColumnIndex(COLUMN_JSON)
            if (columnIndex < 0 || cursor.isNull(columnIndex)) null else cursor.getString(columnIndex)
        }
    }

    private fun writeTelegramConfig(json: String): Boolean {
        val values = ContentValues().apply { put(COLUMN_JSON, json) }
        return contentResolver.update(telegramConfigUri(), values, null, null) == 1
    }

    private fun telegramConfigUri(): Uri {
        return Uri.Builder()
            .scheme("content")
            .authority(hostContext()[KEY_DATA_AUTHORITY] as String)
            .appendPath(TELEGRAM_CONFIG_PATH)
            .build()
    }

    private fun captureHostIntent(intent: Intent?): Boolean {
        if (intent == null || !intent.hasExtra(EXTRA_HOST_PACKAGE)) {
            return false
        }
        val hostPackage = intent.getStringExtra(EXTRA_HOST_PACKAGE)?.takeIf { it.isNotBlank() }
            ?: return false
        val dataAuthority = intent.getStringExtra(EXTRA_HOST_DATA_AUTHORITY)
            ?.takeIf { it == "$hostPackage.optional_plugins.data" }
            ?: return false
        getSharedPreferences(HOST_PREFERENCES, MODE_PRIVATE)
            .edit()
            .putString(KEY_HOST_PACKAGE, hostPackage)
            .putString(KEY_DATA_AUTHORITY, dataAuthority)
            .apply()
        proxyPort = if (intent.hasExtra(EXTRA_PROXY_PORT)) {
            intent.getIntExtra(EXTRA_PROXY_PORT, 0).takeIf { it in 1..65535 }
        } else {
            null
        }
        return true
    }

    private fun hostContext(): Map<String, Any?> {
        val preferences = getSharedPreferences(HOST_PREFERENCES, MODE_PRIVATE)
        return mapOf(
            KEY_HOST_PACKAGE to
                (preferences.getString(KEY_HOST_PACKAGE, null) ?: DEFAULT_HOST_PACKAGE),
            KEY_DATA_AUTHORITY to
                (preferences.getString(KEY_DATA_AUTHORITY, null) ?: DEFAULT_DATA_AUTHORITY),
            KEY_PROXY_PORT to proxyPort,
        )
    }

    companion object {
        private const val CHANNEL_NAME = "lightly.telegram_plugin/host"
        private const val METHOD_GET_HOST_CONTEXT = "getHostContext"
        private const val METHOD_HOST_CONTEXT_CHANGED = "hostContextChanged"
        private const val METHOD_READ_TELEGRAM_CONFIG = "readTelegramConfig"
        private const val METHOD_WRITE_TELEGRAM_CONFIG = "writeTelegramConfig"
        private const val ARG_JSON = "json"
        private const val COLUMN_JSON = "json"
        private const val TELEGRAM_CONFIG_PATH = "telegram_config"
        private const val EXTRA_HOST_PACKAGE = "lightly.host.PACKAGE"
        private const val EXTRA_HOST_DATA_AUTHORITY = "lightly.host.DATA_AUTHORITY"
        private const val EXTRA_PROXY_PORT = "proxyPort"
        private const val HOST_PREFERENCES = "lightly_host"
        private const val KEY_HOST_PACKAGE = "hostPackage"
        private const val KEY_DATA_AUTHORITY = "dataAuthority"
        private const val KEY_PROXY_PORT = "proxyPort"
        private const val DEFAULT_HOST_PACKAGE = "lightly.tool"
        private const val DEFAULT_DATA_AUTHORITY = "lightly.tool.optional_plugins.data"
        private const val ERROR_INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
        private const val ERROR_HOST_ACCESS_DENIED = "HOST_ACCESS_DENIED"
        private const val ERROR_HOST_UNAVAILABLE = "HOST_UNAVAILABLE"
    }
}
