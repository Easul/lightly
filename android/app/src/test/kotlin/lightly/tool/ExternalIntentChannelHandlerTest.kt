package lightly.tool

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExternalIntentChannelHandlerTest {
    @Test
    fun `returns initial intent URL once and detaches the task`() {
        val platform = FakeExternalIntentPlatform()
        val handler = ExternalIntentChannelHandler(platform)
        handler.updateInitialIntentUrl("content://document/1")
        val firstResult = ExternalIntentRecordingResult()
        val secondResult = ExternalIntentRecordingResult()

        assertTrue(handler.handle(MethodCall("getInitialIntentUrl", null), firstResult))
        handler.handle(MethodCall("getInitialIntentUrl", null), secondResult)
        handler.handle(MethodCall("detachExternalIntent", null), ExternalIntentRecordingResult())

        assertEquals("content://document/1", firstResult.successValue)
        assertNull(secondResult.successValue)
        assertTrue(platform.detached)
    }

    @Test
    fun `maps imported document operations`() {
        val platform = FakeExternalIntentPlatform()
        val handler = ExternalIntentChannelHandler(platform)
        val mimeResult = ExternalIntentRecordingResult()
        val importResult = ExternalIntentRecordingResult()
        val cleanupResult = ExternalIntentRecordingResult()

        handler.handle(
            MethodCall("getContentMimeType", mapOf("uri" to "content://document/1")),
            mimeResult,
        )
        handler.handle(
            MethodCall(
                "importContentUriToPrivateFile",
                mapOf("uri" to "content://document/1"),
            ),
            importResult,
        )
        handler.handle(
            MethodCall(
                "cleanupImportedPrivateFiles",
                mapOf("retainedUrls" to listOf("file:///private/keep.txt")),
            ),
            cleanupResult,
        )

        assertEquals("text/plain", mimeResult.successValue)
        assertEquals("file:///private/import.txt", importResult.successValue)
        assertEquals(listOf("file:///private/keep.txt"), platform.retainedUrls)
        assertEquals(true, cleanupResult.successValue)
    }

    @Test
    fun `rejects blank import URI`() {
        val result = ExternalIntentRecordingResult()

        ExternalIntentChannelHandler(FakeExternalIntentPlatform()).handle(
            MethodCall("importContentUriToPrivateFile", mapOf("uri" to "")),
            result,
        )

        assertEquals("INVALID_URI", result.errorCode)
    }
}

private class FakeExternalIntentPlatform : ExternalIntentPlatform {
    var detached = false
    var retainedUrls: List<String>? = null

    override fun detachExternalIntent() {
        detached = true
    }

    override fun importContentUriToPrivateFile(uri: String): String {
        return "file:///private/import.txt"
    }

    override fun getContentMimeType(uri: String): String = "text/plain"

    override fun cleanupImportedPrivateFiles(retainedUrls: List<String>): Boolean {
        this.retainedUrls = retainedUrls
        return true
    }
}

private class ExternalIntentRecordingResult : MethodChannel.Result {
    var successValue: Any? = null
    var errorCode: String? = null

    override fun success(result: Any?) {
        successValue = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        this.errorCode = errorCode
    }

    override fun notImplemented() = Unit
}
