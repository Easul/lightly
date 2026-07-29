package lightly.tool.plugin.webrtc

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle

class AudioPermissionActivity : Activity() {
    private var completed = false
    private var permissionRequestActive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val missingPermissions = requiredPermissions().filterNot(::isPermissionGranted)
        if (missingPermissions.isEmpty()) {
            return
        }
        permissionRequestActive = true
        requestPermissions(missingPermissions.toTypedArray(), REQUEST_AUDIO_PERMISSIONS)
    }

    override fun onResume() {
        super.onResume()
        if (!completed && !permissionRequestActive && isPermissionGranted(Manifest.permission.RECORD_AUDIO)) {
            finishWithResult(true)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_AUDIO_PERMISSIONS) {
            permissionRequestActive = false
            finishWithResult(isPermissionGranted(Manifest.permission.RECORD_AUDIO))
        }
    }

    private fun requiredPermissions(): List<String> = buildList {
        add(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            add(Manifest.permission.BLUETOOTH_CONNECT)
        }
    }

    private fun isPermissionGranted(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

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
        private const val REQUEST_AUDIO_PERMISSIONS = 1
    }
}
