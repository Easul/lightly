package lightly.tool

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StorageAccessChannelHandlerTest {
    @Test
    fun `maps path and permission checks`() {
        val platform = FakeStorageAccessPlatform(permissionGranted = true)
        val handler = StorageAccessChannelHandler(platform)
        val pathResult = StorageRecordingResult()
        val permissionResult = StorageRecordingResult()

        assertTrue(handler.handle(MethodCall("getSharedDownloadsPath", null), pathResult))
        assertTrue(handler.handle(MethodCall("hasFileAccessPermission", null), permissionResult))

        assertEquals("/storage/emulated/0/Download", pathResult.successValue)
        assertEquals(true, permissionResult.successValue)
    }

    @Test
    fun `completes a pending permission request from the activity result`() {
        val platform = FakeStorageAccessPlatform(permissionGranted = false)
        val handler = StorageAccessChannelHandler(platform)
        val result = StorageRecordingResult()

        handler.handle(MethodCall("requestFileAccessPermission", null), result)

        assertTrue(platform.requested)
        assertEquals(4101, platform.manageRequestCode)
        assertEquals(4102, platform.readRequestCode)
        platform.permissionGranted = true
        assertTrue(handler.handlePermissionResult(4101))
        assertEquals(true, result.successValue)
    }

    @Test
    fun `rejects a second permission request while one is pending`() {
        val handler = StorageAccessChannelHandler(
            FakeStorageAccessPlatform(permissionGranted = false),
        )
        val firstResult = StorageRecordingResult()
        val secondResult = StorageRecordingResult()

        handler.handle(MethodCall("requestFileAccessPermission", null), firstResult)
        handler.handle(MethodCall("requestFileAccessPermission", null), secondResult)

        assertEquals("IN_PROGRESS", secondResult.errorCode)
        assertFalse(handler.handlePermissionResult(9999))
    }
}

private class FakeStorageAccessPlatform(
    var permissionGranted: Boolean,
) : StorageAccessPlatform {
    var requested = false
    var manageRequestCode: Int? = null
    var readRequestCode: Int? = null

    override fun getSharedDownloadsPath(): String = "/storage/emulated/0/Download"

    override fun hasFileAccessPermission(): Boolean = permissionGranted

    override fun requestFileAccessPermission(
        manageStorageRequestCode: Int,
        readStorageRequestCode: Int,
    ) {
        requested = true
        manageRequestCode = manageStorageRequestCode
        readRequestCode = readStorageRequestCode
    }
}

private class StorageRecordingResult : MethodChannel.Result {
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
