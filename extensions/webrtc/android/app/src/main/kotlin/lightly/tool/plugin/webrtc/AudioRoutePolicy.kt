package lightly.tool.plugin.webrtc

import android.media.AudioDeviceInfo

internal object AudioRoutePolicy {
    private val wiredDeviceTypes = listOf(
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY,
    )

    private val bluetoothCommunicationDeviceTypes = listOf(
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_HEARING_AID,
    )

    fun preferredCommunicationDeviceType(availableTypes: List<Int>): Int? =
        wiredDeviceTypes.firstOrNull(availableTypes::contains)
            ?: bluetoothCommunicationDeviceTypes.firstOrNull(availableTypes::contains)

    fun routeName(deviceType: Int): String = when (deviceType) {
        in wiredDeviceTypes -> "wired"
        in bluetoothCommunicationDeviceTypes -> "bluetooth"
        else -> "unknown"
    }
}
