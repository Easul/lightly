package lightly.tool.plugin.easytier

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EasyTierRuntimeControllerTest {
    @Test
    fun `parses starts and stops no-tun runtime without vpn permission`() {
        val native = FakeNativeRuntime()
        val vpn = FakeVpnPlatform(hasPermission = false)
        val state = FakeStateStore()
        val scheduler = FakeMonitorScheduler()
        val controller = EasyTierRuntimeController(native, vpn, state, scheduler)

        assertTrue(controller.parseConfig("instance_name = \"test\""))
        assertTrue(
            controller.startNetwork(
                "instance_name = \"test\"",
                "test",
                androidVpn = false,
            ),
        )
        assertEquals("instance_name = \"test\"", native.startedConfig)
        assertEquals("test", state.startedInstanceName)
        assertEquals(1, scheduler.startCount)
        assertTrue(vpn.stopCount >= 1)

        assertTrue(controller.stopNetwork())
        assertTrue(native.stopped)
        assertTrue(state.cleared)
    }

    @Test
    fun `requires plugin vpn permission before starting tun runtime`() {
        val native = FakeNativeRuntime()
        val controller = EasyTierRuntimeController(
            native,
            FakeVpnPlatform(hasPermission = false),
            FakeStateStore(),
            FakeMonitorScheduler(),
        )

        assertFalse(
            controller.startNetwork("instance_name = \"vpn\"", "vpn", androidVpn = true),
        )
        assertEquals(null, native.startedConfig)
        assertEquals("VPN permission is required", controller.getLastError())
    }

    @Test
    fun `extracts virtual ipv4 using the existing numeric address contract`() {
        val info = org.json.JSONObject(
            """{"my_node_info":{"virtual_ipv4":{"address":{"addr":176061974},"network_length":24}}}""",
        )

        assertEquals("10.126.126.22/24", EasyTierRuntimeController.extractVirtualIpv4(info))
    }

    @Test
    fun `returns monitored network info without another native collection`() {
        val native = FakeNativeRuntime()
        val state = FakeStateStore().apply {
            rawNetworkInfo = """{"map":{"test":{"running":true}}}"""
        }
        val controller = EasyTierRuntimeController(
            native,
            FakeVpnPlatform(hasPermission = true),
            state,
            FakeMonitorScheduler(),
        )

        assertEquals(state.rawNetworkInfo, controller.getNetworkInfo())
        assertEquals(0, native.collectCount)
    }
}

private class FakeNativeRuntime : EasyTierNativeRuntime {
    var startedConfig: String? = null
    var stopped = false
    var collectCount = 0

    override fun parseConfig(config: String): Int = 0
    override fun runNetworkInstance(config: String): Int {
        startedConfig = config
        return 0
    }
    override fun stopAllInstances() { stopped = true }
    override fun collectNetworkInfos(): String? {
        collectCount += 1
        return """{"map":{}}"""
    }
    override fun getLastError(): String? = null
}

private class FakeVpnPlatform(var hasPermission: Boolean) : EasyTierVpnPlatform {
    var stopCount = 0
    override fun hasVpnPermission(): Boolean = hasPermission
    override fun restartVpnService(instanceName: String, ipv4: String) = Unit
    override fun stopVpnService() { stopCount += 1 }
}

private class FakeStateStore : EasyTierRuntimeStateStore {
    var startedInstanceName: String? = null
    var rawNetworkInfo: String? = null
    var cleared = false
    override fun markStarted(instanceName: String) { startedInstanceName = instanceName }
    override fun updateFromNetworkInfo(
        instanceName: String,
        json: String,
        virtualIpv4: String?,
        running: Boolean,
    ) {
        rawNetworkInfo = json
    }
    override fun rawNetworkInfo(): String? = rawNetworkInfo
    override fun clear() { cleared = true }
}

private class FakeMonitorScheduler : EasyTierMonitorScheduler {
    var startCount = 0
    override fun start(task: () -> Unit) { startCount += 1 }
    override fun stop() = Unit
}
