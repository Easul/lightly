package lightly.tool.plugin.webrtc

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle

class AudioPermissionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            finishWithResult(true)
            return
        }
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_RECORD_AUDIO) {
            finishWithResult(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        }
    }

    private fun finishWithResult(granted: Boolean) {
        setResult(if (granted) RESULT_OK else RESULT_CANCELED)
        finish()
    }

    companion object {
        private const val REQUEST_RECORD_AUDIO = 1
    }
}
