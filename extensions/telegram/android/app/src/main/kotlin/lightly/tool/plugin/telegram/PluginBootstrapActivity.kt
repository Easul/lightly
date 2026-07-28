package lightly.tool.plugin.telegram

import android.app.Activity
import android.os.Bundle

/** Lets a foreground Lightly interaction activate this companion before its bound service starts. */
class PluginBootstrapActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_OK)
        finish()
        overridePendingTransition(0, 0)
    }
}
