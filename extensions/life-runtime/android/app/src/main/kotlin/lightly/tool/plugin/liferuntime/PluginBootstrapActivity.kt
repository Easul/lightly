package lightly.tool.plugin.liferuntime

import android.app.Activity
import android.os.Bundle

/** Establishes a foreground activation path before Lightly binds the runtime service. */
class PluginBootstrapActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_OK)
        finish()
        overridePendingTransition(0, 0)
    }
}
