package lightly.tool

import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteControlChannelHandlerTest {
    @Test
    fun `maps session startup and command arguments`() {
        val session = FakeRemoteControlNativeSession()
        val handler = createRemoteHandler(session = session)

        handler.handle(
            MethodCall(
                "startReceiver",
                mapOf(
                    "controlPort" to 18082,
                    "screenPort" to 18083,
                    "screenFps" to 12,
                    "screenBitrate" to 2_500_000,
                ),
            ),
            RemoteRecordingResult(),
        )
        handler.handle(
            MethodCall("startController", mapOf("host" to "10.126.126.2")),
            RemoteRecordingResult(),
        )
        handler.handle(
            MethodCall("executeCommand", mapOf("command" to "{\"type\":\"global\"}")),
            RemoteRecordingResult(),
        )

        assertEquals(listOf(18082, 18083, 12, 2_500_000), session.receiverArguments)
        assertEquals("10.126.126.2", session.controllerHost)
        assertEquals("{\"type\":\"global\"}", session.command)
    }

    @Test
    fun `keeps screen frame bytes on the direct binary path`() {
        val texture = FakeRemoteControlScreenTexture()
        val handler = createRemoteHandler(screenTexture = texture)
        val data = byteArrayOf(1, 2, 3)
        val result = RemoteRecordingResult()

        handler.handle(
            MethodCall(
                "pushScreenFrame",
                mapOf("data" to data, "type" to 1, "timestamp" to 1234L),
            ),
            result,
        )

        assertSame(data, texture.data)
        assertEquals(1, texture.type)
        assertEquals(1234L, texture.timestamp)
        assertEquals(true, result.successValue)
    }

    @Test
    fun `guards concurrent screen capture permission requests`() {
        val session = FakeRemoteControlNativeSession()
        val handler = createRemoteHandler(session = session)
        val firstResult = RemoteRecordingResult()
        val secondResult = RemoteRecordingResult()

        handler.handle(
            MethodCall("startScreenCapture", mapOf("fps" to 10, "bitrate" to 1_800_000)),
            firstResult,
        )
        handler.handle(
            MethodCall("startScreenCapture", mapOf("fps" to 15, "bitrate" to 2_000_000)),
            secondResult,
        )

        assertEquals(listOf(10, 1_800_000), session.captureArguments)
        assertEquals("IN_PROGRESS", secondResult.errorCode)
        assertTrue(
            handler.handleActivityResult(
                RemoteControlService.REQUEST_MEDIA_PROJECTION,
                0,
                null,
            ),
        )
        assertEquals(false, firstResult.successValue)
        assertFalse(handler.handleActivityResult(9999, 0, null))
    }

    @Test
    fun `uses accessibility and screen fallbacks without a session`() {
        val accessibility = FakeRemoteControlAccessibilityPlatform()
        val handler = createRemoteHandler(accessibility = accessibility)
        val overlayResult = RemoteRecordingResult()
        val permissionResult = RemoteRecordingResult()
        val screenResult = RemoteRecordingResult()

        handler.handle(
            MethodCall("showDisconnectOverlay", mapOf("message" to "offline")),
            overlayResult,
        )
        handler.handle(MethodCall("checkAccessibilityPermission", null), permissionResult)
        handler.handle(MethodCall("getScreenInfo", null), screenResult)

        assertEquals("offline", accessibility.overlayMessage)
        assertEquals(true, overlayResult.successValue)
        assertEquals(true, permissionResult.successValue)
        assertEquals(
            mapOf("width" to 1080, "height" to 2340, "density" to 2.75),
            screenResult.successValue,
        )
    }

    @Test
    fun `rejects a missing command and missing frame data`() {
        val handler = createRemoteHandler()
        val commandResult = RemoteRecordingResult()
        val frameResult = RemoteRecordingResult()

        handler.handle(MethodCall("executeCommand", null), commandResult)
        handler.handle(MethodCall("pushScreenFrame", null), frameResult)

        assertEquals("INVALID_ARGUMENT", commandResult.errorCode)
        assertEquals("INVALID_ARGS", frameResult.errorCode)
        assertNull(commandResult.successValue)
        assertNull(frameResult.successValue)
    }
}

private fun createRemoteHandler(
    session: FakeRemoteControlNativeSession = FakeRemoteControlNativeSession(),
    accessibility: FakeRemoteControlAccessibilityPlatform =
        FakeRemoteControlAccessibilityPlatform(),
    screenTexture: FakeRemoteControlScreenTexture = FakeRemoteControlScreenTexture(),
): RemoteControlChannelHandler {
    return RemoteControlChannelHandler(
        sessionFactory = { session },
        accessibility = accessibility,
        screenTexture = screenTexture,
        callbackDispatcher = RemoteControlCallbackDispatcher { action -> action() },
    )
}

private class FakeRemoteControlNativeSession : RemoteControlNativeSession {
    var receiverArguments: List<Int>? = null
    var controllerHost: String? = null
    var command: String? = null
    var captureArguments: List<Int>? = null

    override fun startReceiver(controlPort: Int, screenPort: Int, fps: Int, bitrate: Int) {
        receiverArguments = listOf(controlPort, screenPort, fps, bitrate)
    }

    override fun startController(host: String) {
        controllerHost = host
    }

    override fun stop() = Unit

    override fun executeCommand(command: String) {
        this.command = command
    }

    override fun getScreenInfo(): Map<String, Any> = emptyMap()

    override fun startScreenCapture(
        fps: Int,
        bitrate: Int,
        onFrame: (ByteArray, Boolean) -> Unit,
        onConfig: (ByteArray, ByteArray) -> Unit,
    ) {
        captureArguments = listOf(fps, bitrate)
    }

    override fun handleMediaProjectionResult(
        resultCode: Int,
        data: Intent,
        fps: Int,
        bitrate: Int,
    ) = Unit

    override fun stopScreenCapture() = Unit
    override fun requestKeyFrame() = Unit
    override fun updateBitrate(bitrate: Int) = Unit
}

private class FakeRemoteControlAccessibilityPlatform : RemoteControlAccessibilityPlatform {
    var overlayMessage: String? = null

    override fun showDisconnectOverlay(message: String): Boolean {
        overlayMessage = message
        return true
    }

    override fun isRunning(): Boolean = true

    override fun openSettings() = Unit
}

private class FakeRemoteControlScreenTexture : RemoteControlScreenTexture {
    var data: ByteArray? = null
    var type: Int? = null
    var timestamp: Long? = null

    override fun create(width: Int, height: Int): Long = 42L

    override fun pushFrame(data: ByteArray, type: Int, timestamp: Long) {
        this.data = data
        this.type = type
        this.timestamp = timestamp
    }

    override fun dispose() = Unit
}

private class RemoteRecordingResult : MethodChannel.Result {
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
