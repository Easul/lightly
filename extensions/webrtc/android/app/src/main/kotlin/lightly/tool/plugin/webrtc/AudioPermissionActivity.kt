package lightly.tool.plugin.webrtc

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle

class AudioPermissionActivity : Activity() {
    private var completed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO)
    }

    override fun onResume() {
        super.onResume()
        if (!completed &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        ) {
            finishWithResult(true)
        }
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
        if (completed) return
        completed = true
        val foregroundStarted = granted && startVoiceForegroundService()
        setResult(if (foregroundStarted) RESULT_OK else RESULT_CANCELED)
        finish()
    }

    private fun startVoiceForegroundService(): Boolean {
        val intent = Intent(this, WebRtcVoicePluginService::class.java)
            .setAction(WebRtcVoicePluginService.ACTION_START_VOICE_FOREGROUND)
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        }.isSuccess
    }

    companion object {
        private const val REQUEST_RECORD_AUDIO = 1
    }
}
