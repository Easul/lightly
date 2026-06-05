package lightly.tool

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EasyTierStateStoreTest {
    @Test
    fun storesAndClearsNetworkInfoSnapshot() {
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
        assertEquals("{\"map\":{}}", snapshot.rawNetworkInfoJson)
        assertEquals("10.126.126.22/24", snapshot.virtualIpv4)
        assertTrue(snapshot.isRunning)
        assertNull(snapshot.errorMessage)

        EasyTierStateStore.clear()

        val cleared = EasyTierStateStore.snapshot()
        assertNull(cleared.instanceName)
        assertNull(cleared.rawNetworkInfoJson)
        assertNull(cleared.virtualIpv4)
        assertFalse(cleared.isRunning)
    }
}
