package lightly.tool

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EasyTierChannelHandlerTest {
    @Test
    fun `maps all synchronous channel methods`() {
        val native = FakeEasyTierNativeRuntime()
        val stateStore = FakeEasyTierStateStore()
        val handler = createHandler(native = native, stateStore = stateStore)
        val parseResult = EasyTierRecordingResult()
        val permissionResult = EasyTierRecordingResult()
        val infoResult = EasyTierRecordingResult()
        val errorResult = EasyTierRecordingResult()

        handler.handle(
            MethodCall("parseConfig", mapOf("config" to "instance_name = \"test\"")),
            parseResult,
        )
        handler.handle(MethodCall("checkVpnPermission", null), permissionResult)
        handler.handle(MethodCall("getNetworkInfo", null), infoResult)
        handler.handle(MethodCall("getLastError", null), errorResult)

        assertEquals(true, parseResult.successValue)
        assertEquals(true, permissionResult.successValue)
        assertEquals(native.networkInfo, infoResult.successValue)
        assertEquals("native error", errorResult.successValue)
        assertTrue(stateStore.refreshed)
    }

    @Test
    fun `starts and stops no-tun mode without Android VPN permission`() {
        val native = FakeEasyTierNativeRuntime()
        val vpnPlatform = FakeEasyTierVpnPlatform(hasPermission = false)
        val stateStore = FakeEasyTierStateStore()
        val scheduler = FakeEasyTierMonitorScheduler()
        val handler = createHandler(
            native = native,
            vpnPlatform = vpnPlatform,
            stateStore = stateStore,
            scheduler = scheduler,
        )
        val startResult = EasyTierRecordingResult()
        val stopResult = EasyTierRecordingResult()

        handler.handle(
            MethodCall(
                "startVpn",
                mapOf(
                    "config" to "instance_name = \"test\"",
                    "instanceName" to "test",
                    "useAndroidVpn" to false,
                ),
            ),
            startResult,
        )
        assertEquals(1, scheduler.startCount)
        handler.handle(MethodCall("stopVpn", null), stopResult)

        assertEquals(true, startResult.successValue)
        assertEquals("instance_name = \"test\"", native.startedConfig)
        assertEquals("test", stateStore.startedInstanceName)
        assertEquals(listOf(true, true), vpnPlatform.forceStopValues)
        assertTrue(native.stopped)
        assertTrue(stateStore.cleared)
        assertEquals(true, stopResult.successValue)
    }

    @Test
    fun `defers Android VPN startup until permission result`() {
        val native = FakeEasyTierNativeRuntime()
        val vpnPlatform = FakeEasyTierVpnPlatform(hasPermission = false)
        val handler = createHandler(native = native, vpnPlatform = vpnPlatform)
        val result = EasyTierRecordingResult()

        handler.handle(
            MethodCall(
                "startVpn",
                mapOf(
                    "config" to "instance_name = \"vpn\"",
                    "instanceName" to "vpn",
                    "useAndroidVpn" to true,
                ),
            ),
            result,
        )

        assertEquals(4103, vpnPlatform.permissionRequestCode)
        assertEquals(null, native.startedConfig)
        assertTrue(handler.handleActivityResult(4103, -1))
        assertEquals("instance_name = \"vpn\"", native.startedConfig)
        assertEquals(true, result.successValue)
        assertFalse(handler.handleActivityResult(9999, -1))
    }

    @Test
    fun `preserves route classification`() {
        assertEquals(
            "relay-via-9",
            EasyTierChannelHandler.describeRouteMode(
                cost = 2,
                peerId = 7,
                nextHopPeerId = 9,
                publicServer = false,
                directConnectionCount = 0,
            ),
        )
    }
}

private fun createHandler(
    native: FakeEasyTierNativeRuntime = FakeEasyTierNativeRuntime(),
    vpnPlatform: FakeEasyTierVpnPlatform = FakeEasyTierVpnPlatform(),
    stateStore: FakeEasyTierStateStore = FakeEasyTierStateStore(),
    scheduler: FakeEasyTierMonitorScheduler = FakeEasyTierMonitorScheduler(),
): EasyTierChannelHandler {
    return EasyTierChannelHandler(native, vpnPlatform, stateStore, scheduler)
}

private class FakeEasyTierNativeRuntime : EasyTierNativeRuntime {
    val networkInfo = """{"map":{"test":{"running":true}}}"""
    var startedConfig: String? = null
    var stopped = false

    override fun parseConfig(config: String): Int = 0

    override fun runNetworkInstance(config: String): Int {
        startedConfig = config
        return 0
    }

    override fun stopAllInstances() {
        stopped = true
    }

    override fun collectNetworkInfos(): String = networkInfo

    override fun getLastError(): String = "native error"
}

private class FakeEasyTierVpnPlatform(
    var hasPermission: Boolean = true,
) : EasyTierVpnPlatform {
    var permissionRequestCode: Int? = null
    val forceStopValues = mutableListOf<Boolean>()

    override fun hasVpnPermission(): Boolean = hasPermission

    override fun requestVpnPermission(requestCode: Int) {
        permissionRequestCode = requestCode
    }

    override fun restartVpnService(instanceName: String, ipv4: String) = Unit

    override fun stopVpnService(forceStop: Boolean) {
        forceStopValues += forceStop
    }
}

private class FakeEasyTierStateStore : EasyTierRuntimeStateStore {
    var startedInstanceName: String? = null
    var refreshed = false
    var cleared = false

    override fun markStarted(instanceName: String) {
        startedInstanceName = instanceName
    }

    override fun updateFromNetworkInfo(
        instanceName: String,
        json: String,
        virtualIpv4: String?,
        running: Boolean,
    ) = Unit

    override fun refreshFromNative() {
        refreshed = true
    }

    override fun clear() {
        cleared = true
    }
}

private class FakeEasyTierMonitorScheduler : EasyTierMonitorScheduler {
    var started = false
    var startCount = 0

    override fun start(task: () -> Unit) {
        started = true
        startCount += 1
    }

    override fun stop() {
        started = false
    }
}

private class EasyTierRecordingResult : MethodChannel.Result {
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
