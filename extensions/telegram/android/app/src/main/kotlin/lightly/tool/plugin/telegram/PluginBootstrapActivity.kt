package lightly.tool.plugin.telegram

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle

/** Lets a foreground Lightly interaction activate this companion before its bound service starts. */
class PluginBootstrapActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val serviceIntent = Intent(this, TelegramPluginService::class.java).setAction(
            TelegramPluginService.ACTION_START_FOREGROUND,
        )
        val started = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        }.isSuccess
        setResult(if (started) RESULT_OK else RESULT_CANCELED)
        finish()
        overridePendingTransition(0, 0)
    }
}
