package lightly.tool

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OptionalPluginChannelHandlerTest {
    @Test
    fun `returns plugin status for requested package`() {
        val platform = FakeOptionalPluginPlatform()
        val result = OptionalPluginRecordingResult()

        OptionalPluginChannelHandler(platform).handle(
            MethodCall("getPluginStatus", mapOf("packageName" to "lightly.tool.plugin.telegram")),
            result,
        )

        assertEquals("lightly.tool.plugin.telegram", platform.statusPackageName)
        assertEquals(true, (result.successValue as Map<*, *>)["installed"])
    }

    @Test
    fun `rejects plugin status without package name`() {
        val result = OptionalPluginRecordingResult()

        OptionalPluginChannelHandler(FakeOptionalPluginPlatform()).handle(
            MethodCall("getPluginStatus", emptyMap<String, Any>()),
            result,
        )

        assertEquals("INVALID_ARGUMENTS", result.errorCode)
        assertNull(result.successValue)
    }

    @Test
    fun `maps install arguments and result`() {
        val platform = FakeOptionalPluginPlatform(
            installResult = PluginInstallResult.SIGNATURE_MISMATCH,
        )
        val result = OptionalPluginRecordingResult()

        OptionalPluginChannelHandler(platform).handle(
            MethodCall(
                "installPluginApk",
                mapOf(
                    "path" to "/cache/optional_plugins/telegram.apk",
                    "expectedPackageName" to "lightly.tool.plugin.telegram",
                ),
            ),
            result,
        )

        assertEquals("/cache/optional_plugins/telegram.apk", platform.installPath)
        assertEquals("lightly.tool.plugin.telegram", platform.installPackageName)
        assertEquals("signature_mismatch", result.successValue)
    }

    @Test
    fun `reports supported abi and install permission`() {
        val platform = FakeOptionalPluginPlatform(
            supportedAbi = "arm64-v8a",
            canRequestInstalls = false,
        )
        val handler = OptionalPluginChannelHandler(platform)
        val abiResult = OptionalPluginRecordingResult()
        val permissionResult = OptionalPluginRecordingResult()

        handler.handle(MethodCall("getSupportedAbi", null), abiResult)
        handler.handle(MethodCall("canRequestPackageInstalls", null), permissionResult)

        assertEquals("arm64-v8a", abiResult.successValue)
        assertEquals(false, permissionResult.successValue)
    }
}

private class FakeOptionalPluginPlatform(
    private val supportedAbi: String? = "arm64-v8a",
    private val canRequestInstalls: Boolean = true,
    private val installResult: PluginInstallResult = PluginInstallResult.STARTED,
) : OptionalPluginPlatform {
    var statusPackageName: String? = null
    var installPath: String? = null
    var installPackageName: String? = null

    override fun getSupportedAbi(): String? = supportedAbi

    override fun getPluginStatus(packageName: String): Map<String, Any?> {
        statusPackageName = packageName
        return mapOf("installed" to true, "trusted" to true, "enabled" to true)
    }

    override fun canRequestPackageInstalls(): Boolean = canRequestInstalls

    override fun openInstallPermissionSettings() = Unit

    override fun installPluginApk(
        path: String,
        expectedPackageName: String,
    ): PluginInstallResult {
        installPath = path
        installPackageName = expectedPackageName
        return installResult
    }
}

private class OptionalPluginRecordingResult : MethodChannel.Result {
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
