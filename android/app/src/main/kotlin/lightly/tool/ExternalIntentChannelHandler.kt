package lightly.tool

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ExternalIntentChannelHandler internal constructor(
    private val platform: ExternalIntentPlatform,
) : BrowserPlatformMethodHandler {
    constructor(activity: Activity) : this(AndroidExternalIntentPlatform(activity))

    private var initialIntentUrl: String? = null

    fun updateInitialIntentUrl(url: String?) {
        initialIntentUrl = url
    }

    fun publishNewIntent(channel: MethodChannel, url: String) {
        channel.invokeMethod(METHOD_ON_NEW_INTENT_URL, mapOf(ARG_URL to url))
    }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            METHOD_GET_INITIAL_INTENT_URL -> {
                val url = initialIntentUrl
                initialIntentUrl = null
                result.success(url)
            }

            METHOD_DETACH_EXTERNAL_INTENT -> {
                initialIntentUrl = null
                platform.detachExternalIntent()
                result.success(true)
            }

            METHOD_IMPORT_CONTENT_URI -> importContentUri(call, result)
            METHOD_GET_CONTENT_MIME_TYPE -> getContentMimeType(call, result)
            METHOD_CLEANUP_IMPORTED_FILES -> cleanupImportedFiles(call, result)
            else -> return false
        }
        return true
    }

    private fun importContentUri(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>(ARG_URI)
        if (uri.isNullOrBlank()) {
            result.error(ERROR_INVALID_URI, "URI is required", null)
            return
        }
        try {
            result.success(platform.importContentUriToPrivateFile(uri))
        } catch (error: Exception) {
            result.error(ERROR_IMPORT_FAILED, error.message, null)
        }
    }

    private fun getContentMimeType(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>(ARG_URI)
        if (uri.isNullOrBlank()) {
            result.success(null)
            return
        }
        result.success(runCatching { platform.getContentMimeType(uri) }.getOrNull())
    }

    private fun cleanupImportedFiles(call: MethodCall, result: MethodChannel.Result) {
        val retainedUrls = call.argument<List<String>>(ARG_RETAINED_URLS) ?: emptyList()
        try {
            result.success(platform.cleanupImportedPrivateFiles(retainedUrls))
        } catch (error: Exception) {
            result.error(ERROR_CLEANUP_FAILED, error.message, null)
        }
    }

    companion object {
        private const val METHOD_ON_NEW_INTENT_URL = "onNewIntentUrl"
        private const val METHOD_GET_INITIAL_INTENT_URL = "getInitialIntentUrl"
        private const val METHOD_DETACH_EXTERNAL_INTENT = "detachExternalIntent"
        private const val METHOD_IMPORT_CONTENT_URI = "importContentUriToPrivateFile"
        private const val METHOD_GET_CONTENT_MIME_TYPE = "getContentMimeType"
        private const val METHOD_CLEANUP_IMPORTED_FILES = "cleanupImportedPrivateFiles"
        private const val ARG_URL = "url"
        private const val ARG_URI = "uri"
        private const val ARG_RETAINED_URLS = "retainedUrls"
        private const val ERROR_INVALID_URI = "INVALID_URI"
        private const val ERROR_IMPORT_FAILED = "IMPORT_FAILED"
        private const val ERROR_CLEANUP_FAILED = "CLEANUP_FAILED"
    }
}

internal interface ExternalIntentPlatform {
    fun detachExternalIntent()
    fun importContentUriToPrivateFile(uri: String): String?
    fun getContentMimeType(uri: String): String?
    fun cleanupImportedPrivateFiles(retainedUrls: List<String>): Boolean
}

private class AndroidExternalIntentPlatform(
    private val activity: Activity,
) : ExternalIntentPlatform {
    private val importedFileService by lazy {
        BrowserImportedFileService(activity, "BrowserProxy")
    }

    override fun detachExternalIntent() {
        activity.intent = Intent(activity, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
    }

    override fun importContentUriToPrivateFile(uri: String): String? {
        return importedFileService.importContentUriToPrivateFile(uri)
    }

    override fun getContentMimeType(uri: String): String? {
        return importedFileService.getContentMimeType(uri)
    }

    override fun cleanupImportedPrivateFiles(retainedUrls: List<String>): Boolean {
        return importedFileService.cleanupImportedPrivateFiles(retainedUrls)
    }
}
