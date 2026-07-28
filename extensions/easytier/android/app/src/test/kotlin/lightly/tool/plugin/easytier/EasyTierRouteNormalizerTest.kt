package lightly.tool.plugin.easytier

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class EasyTierRouteNormalizerTest {
    @Test
    fun `normalizes vpn subnet routes`() {
        assertEquals("10.126.126.0", EasyTierRouteNormalizer.toNetworkAddress("10.126.126.22", 24))
        assertEquals("10.126.0.0", EasyTierRouteNormalizer.toNetworkAddress("10.126.126.22", 16))
        assertEquals("10.126.126.22", EasyTierRouteNormalizer.toNetworkAddress("10.126.126.22", 32))
        assertEquals(Pair("192.168.10.0", 24), EasyTierRouteNormalizer.parseRoute("192.168.10.44/24"))
    }

    @Test
    fun `rejects invalid prefix length`() {
        assertThrows(IllegalArgumentException::class.java) {
            EasyTierRouteNormalizer.toNetworkAddress("10.126.126.22", 33)
        }
    }
}
