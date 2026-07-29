package lightly.tool.plugin.easytier

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EasyTierStateStoreTest {
    @Test
    fun `stores and clears network info snapshot`() {
        EasyTierStateStore.clear()
        EasyTierStateStore.markStarted("lightly")
        EasyTierStateStore.updateFromNetworkInfo(
            nextInstanceName = "lightly",
            json = "{\"map\":{}}",
            nextVirtualIpv4 = "10.126.126.22/24",
            running = true,
        )

        val snapshot = EasyTierStateStore.snapshot()
        assertEquals("lightly", snapshot.instanceName)
        assertEquals("10.126.126.22/24", snapshot.virtualIpv4)
        assertTrue(snapshot.isRunning)

        EasyTierStateStore.clear()
        val cleared = EasyTierStateStore.snapshot()
        assertNull(cleared.instanceName)
        assertNull(cleared.virtualIpv4)
        assertFalse(cleared.isRunning)
    }

    @Test
    fun `starting a new instance clears stale monitored data`() {
        EasyTierStateStore.clear()
        EasyTierStateStore.updateFromNetworkInfo(
            nextInstanceName = "old",
            json = "{\"map\":{}}",
            nextVirtualIpv4 = "10.126.126.10/24",
            running = true,
        )

        EasyTierStateStore.markStarted("new")

        val snapshot = EasyTierStateStore.snapshot()
        assertEquals("new", snapshot.instanceName)
        assertNull(snapshot.rawNetworkInfoJson)
        assertNull(snapshot.virtualIpv4)
    }
}
