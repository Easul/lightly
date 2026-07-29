package lightly.tool

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertSame
import org.junit.Test

class H264DecoderTest {
    private val decoder = H264Decoder {}

    @Test
    fun `keeps existing Annex B access units without copying`() {
        val accessUnit = byteArrayOf(0, 0, 0, 1, 0x65, 1, 2, 3)

        val normalized = decoder.normalizeFrameData(accessUnit)

        assertSame(accessUnit, normalized)
    }

    @Test
    fun `converts AVCC access units to Annex B`() {
        val accessUnit = byteArrayOf(0, 0, 0, 2, 0x65, 1, 0, 0, 0, 2, 0x41, 2)

        val normalized = decoder.normalizeFrameData(accessUnit)

        assertArrayEquals(
            byteArrayOf(0, 0, 0, 1, 0x65, 1, 0, 0, 0, 1, 0x41, 2),
            normalized,
        )
    }
}
