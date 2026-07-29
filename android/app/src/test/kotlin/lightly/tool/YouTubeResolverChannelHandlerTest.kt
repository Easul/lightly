package lightly.tool

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class YouTubeResolverChannelHandlerTest {
    @Test
    fun `availability reports missing private resolver`() {
        val result = YouTubeResolverRecordingResult()

        handler(apiVersion = null).handle(MethodCall("availability", null), result)

        val payload = result.successValue as Map<*, *>
        assertFalse(payload["available"] as Boolean)
        assertNull(payload["apiVersion"])
    }

    @Test
    fun `availability reports compatible private resolver`() {
        val result = YouTubeResolverRecordingResult()

        handler(apiVersion = 1).handle(MethodCall("availability", null), result)

        val payload = result.successValue as Map<*, *>
        assertTrue(payload["available"] as Boolean)
        assertEquals(1, payload["apiVersion"])
    }

    @Test
    fun `resolve fails cleanly when private resolver is missing`() {
        val result = YouTubeResolverRecordingResult()

        handler(apiVersion = null).handle(
            MethodCall(
                "resolve",
                mapOf(
                    "url" to "https://www.youtube.com/watch?v=abc123",
                    "proxyRoute" to "DIRECT",
                ),
            ),
            result,
        )

        assertEquals("UNAVAILABLE", result.errorCode)
        assertEquals("当前安装包未包含 YouTube 解析组件", result.errorMessage)
    }

    private fun handler(apiVersion: Int?): YouTubeResolverChannelHandler {
        return YouTubeResolverChannelHandler(
            runtime = object : YouTubeResolverRuntime {
                override fun apiVersion(): Int? = apiVersion

                override fun resolve(
                    url: String,
                    proxyRoute: String,
                ): String {
                    error("resolve should not be called")
                }
            },
        )
    }
}

private class YouTubeResolverRecordingResult : MethodChannel.Result {
    var successValue: Any? = null
    var errorCode: String? = null
    var errorMessage: String? = null

    override fun success(result: Any?) {
        successValue = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        this.errorCode = errorCode
        this.errorMessage = errorMessage
    }

    override fun notImplemented() = Unit
}
