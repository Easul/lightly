package lightly.tool

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BrowserPlatformChannelHandlerTest {
    @Test
    fun `reports proxy override support`() {
        val proxyOverride = FakeBrowserProxyOverride(supported = true)
        val result = RecordingResult()

        val handled = BrowserPlatformChannelHandler(proxyOverride).handle(
            MethodCall("isSupported", null),
            result,
        )

        assertTrue(handled)
        assertEquals(true, result.successValue)
    }

    @Test
    fun `maps set proxy arguments without changing values`() {
        val proxyOverride = FakeBrowserProxyOverride(supported = true)
        val result = RecordingResult()

        val handled = BrowserPlatformChannelHandler(proxyOverride).handle(
            MethodCall(
                "setProxy",
                mapOf(
                    "host" to "127.0.0.1",
                    "port" to 23333,
                    "scheme" to "HTTP",
                    "bypassDomains" to listOf(" Example.COM ", ""),
                ),
            ),
            result,
        )

        assertTrue(handled)
        assertEquals("127.0.0.1", proxyOverride.host)
        assertEquals(23333, proxyOverride.port)
        assertEquals("HTTP", proxyOverride.scheme)
        assertEquals(listOf(" Example.COM ", ""), proxyOverride.bypassDomains)
        assertEquals(true, result.successValue)
    }

    @Test
    fun `rejects invalid set proxy arguments`() {
        val result = RecordingResult()

        BrowserPlatformChannelHandler(FakeBrowserProxyOverride(supported = true)).handle(
            MethodCall("setProxy", mapOf("host" to "", "port" to 23333)),
            result,
        )

        assertEquals("INVALID_ARGUMENTS", result.errorCode)
        assertNull(result.successValue)
    }

    @Test
    fun `clear proxy returns false when override is unsupported`() {
        val proxyOverride = FakeBrowserProxyOverride(supported = false)
        val result = RecordingResult()

        BrowserPlatformChannelHandler(proxyOverride).handle(
            MethodCall("clearProxy", null),
            result,
        )

        assertEquals(false, result.successValue)
        assertFalse(proxyOverride.clearCalled)
    }

    @Test
    fun `leaves unrelated methods for the fallback handler`() {
        val result = RecordingResult()

        val handled = BrowserPlatformChannelHandler(
            FakeBrowserProxyOverride(supported = true),
        ).handle(MethodCall("getInitialIntentUrl", null), result)

        assertFalse(handled)
        assertNull(result.successValue)
        assertNull(result.errorCode)
    }

    @Test
    fun `desktop metadata handler forwards normalized arguments`() {
        var appliedId: String? = null
        var appliedUserAgent: String? = null
        val handler = BrowserUserAgentMetadataHandler { webViewId, userAgent ->
            appliedId = webViewId
            appliedUserAgent = userAgent
            true
        }
        val result = RecordingResult()

        val handled = handler.handle(
            MethodCall(
                "applyDesktopUserAgentMetadata",
                mapOf("webViewId" to 42, "userAgent" to " Desktop UA "),
            ),
            result,
        )

        assertTrue(handled)
        assertEquals("42", appliedId)
        assertEquals("Desktop UA", appliedUserAgent)
        assertEquals(true, result.successValue)
    }

    @Test
    fun `desktop user agent platform follows custom override`() {
        assertEquals("Windows", desktopPlatformForUserAgent("Windows NT 10.0").name)
        assertEquals("macOS", desktopPlatformForUserAgent("Macintosh; Intel Mac OS X").name)
        assertEquals("Chrome OS", desktopPlatformForUserAgent("CrOS x86_64").name)
        assertEquals("Linux", desktopPlatformForUserAgent("X11; Linux x86_64").name)
    }
}

private class FakeBrowserProxyOverride(
    private val supported: Boolean,
) : BrowserProxyOverride {
    var host: String? = null
    var port: Int? = null
    var scheme: String? = null
    var bypassDomains: List<String>? = null
    var clearCalled = false

    override fun isSupported(): Boolean = supported

    override fun setProxy(
        host: String,
        port: Int,
        scheme: String,
        bypassDomains: List<String>,
        onComplete: () -> Unit,
    ) {
        this.host = host
        this.port = port
        this.scheme = scheme
        this.bypassDomains = bypassDomains
        onComplete()
    }

    override fun clearProxy(onComplete: () -> Unit) {
        clearCalled = true
        onComplete()
    }
}

private class RecordingResult : MethodChannel.Result {
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
