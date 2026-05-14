package lightly.tool

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class EasyTierRouteNormalizerTest {

    @Test
    fun `normalizes host ip to slash24 network`() {
        assertEquals(
            "10.126.126.0",
            EasyTierRouteNormalizer.toNetworkAddress("10.126.126.22", 24),
        )
    }

    @Test
    fun `normalizes host ip to slash16 network`() {
        assertEquals(
            "10.126.0.0",
            EasyTierRouteNormalizer.toNetworkAddress("10.126.126.22", 16),
        )
    }

    @Test
    fun `preserves slash32 host route`() {
        assertEquals(
            "10.126.126.22",
            EasyTierRouteNormalizer.toNetworkAddress("10.126.126.22", 32),
        )
    }

    @Test
    fun `normalizes cidr route before adding it`() {
        assertEquals(
            Pair("192.168.10.0", 24),
            EasyTierRouteNormalizer.parseRoute("192.168.10.44/24"),
        )
    }

    @Test
    fun `rejects invalid prefix length`() {
        assertThrows(IllegalArgumentException::class.java) {
            EasyTierRouteNormalizer.toNetworkAddress("10.126.126.22", 33)
        }
    }
}
