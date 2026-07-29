package lightly.tool.plugin.webrtc

import android.media.AudioDeviceInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioRoutePolicyTest {
    @Test
    fun `wired headset takes priority over bluetooth headset`() {
        val selected = AudioRoutePolicy.preferredCommunicationDeviceType(
            listOf(
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
            ),
        )

        assertEquals(AudioDeviceInfo.TYPE_WIRED_HEADSET, selected)
    }

    @Test
    fun `selects classic bluetooth headset`() {
        val selected = AudioRoutePolicy.preferredCommunicationDeviceType(
            listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BLUETOOTH_SCO),
        )

        assertEquals(AudioDeviceInfo.TYPE_BLUETOOTH_SCO, selected)
        assertEquals("bluetooth", AudioRoutePolicy.routeName(selected!!))
    }

    @Test
    fun `selects bluetooth low energy headset`() {
        val selected = AudioRoutePolicy.preferredCommunicationDeviceType(
            listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BLE_HEADSET),
        )

        assertEquals(AudioDeviceInfo.TYPE_BLE_HEADSET, selected)
    }

    @Test
    fun `selects hearing aid as bluetooth communication route`() {
        val selected = AudioRoutePolicy.preferredCommunicationDeviceType(
            listOf(AudioDeviceInfo.TYPE_HEARING_AID),
        )

        assertEquals(AudioDeviceInfo.TYPE_HEARING_AID, selected)
    }

    @Test
    fun `uses speaker fallback when no headset is available`() {
        val selected = AudioRoutePolicy.preferredCommunicationDeviceType(
            listOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE, AudioDeviceInfo.TYPE_BUILTIN_SPEAKER),
        )

        assertNull(selected)
    }

    @Test
    fun `does not treat media-only bluetooth output as communication headset`() {
        assertTrue(
            AudioRoutePolicy.isBluetoothCommunicationDeviceType(
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            ),
        )
        assertTrue(
            AudioRoutePolicy.isBluetoothCommunicationDeviceType(
                AudioDeviceInfo.TYPE_BLE_HEADSET,
            ),
        )
        assertFalse(
            AudioRoutePolicy.isBluetoothCommunicationDeviceType(
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            ),
        )
    }
}
