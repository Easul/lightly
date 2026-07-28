package lightly.tool.plugin.easytier

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle

class EasyTierVpnPermissionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent == null) {
            finishWithResult(true)
        } else {
            startActivityForResult(permissionIntent, REQUEST_VPN_PERMISSION)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN_PERMISSION) {
            finishWithResult(resultCode == RESULT_OK)
        }
    }

    private fun finishWithResult(granted: Boolean) {
        setResult(if (granted) RESULT_OK else RESULT_CANCELED)
        finish()
    }

    companion object {
        private const val REQUEST_VPN_PERMISSION = 1
    }
}
