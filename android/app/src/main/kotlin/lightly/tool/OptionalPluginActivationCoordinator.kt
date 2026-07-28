package lightly.tool

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager

/**
 * Starts a signature-protected, transparent companion Activity before binding its Service.
 *
 * Some Android builds reject direct cross-package service activation as background autostart.
 * A user-initiated foreground Activity transition establishes the companion process first.
 */
class OptionalPluginActivationCoordinator(private val activity: Activity) {
    private data class PendingActivation(
        val onActivated: () -> Unit,
        val onFailure: () -> Unit,
    )

    private val pendingActivations = mutableMapOf<Int, PendingActivation>()
    private var nextRequestCode = REQUEST_CODE_START

    fun activate(
        pluginPackage: String,
        bootstrapActivityClass: String,
        onActivated: () -> Unit,
        onFailure: () -> Unit,
    ) {
        val signaturesMatch = runCatching {
            activity.packageManager.checkSignatures(
                activity.packageName,
                pluginPackage,
            ) == PackageManager.SIGNATURE_MATCH
        }.getOrDefault(false)
        if (!signaturesMatch) {
            onFailure()
            return
        }

        val requestCode = nextRequestCode()
        pendingActivations[requestCode] = PendingActivation(onActivated, onFailure)
        val intent = Intent().setComponent(
            ComponentName(pluginPackage, bootstrapActivityClass),
        ).addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
        runCatching {
            activity.startActivityForResult(intent, requestCode)
            activity.overridePendingTransition(0, 0)
        }.onFailure {
            pendingActivations.remove(requestCode)?.onFailure?.invoke()
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        val pending = pendingActivations.remove(requestCode) ?: return false
        if (resultCode == Activity.RESULT_OK) {
            pending.onActivated()
        } else {
            pending.onFailure()
        }
        return true
    }

    fun clear() {
        pendingActivations.clear()
    }

    private fun nextRequestCode(): Int {
        repeat(REQUEST_CODE_COUNT) {
            val requestCode = nextRequestCode
            nextRequestCode = if (nextRequestCode == REQUEST_CODE_END) {
                REQUEST_CODE_START
            } else {
                nextRequestCode + 1
            }
            if (requestCode !in pendingActivations) {
                return requestCode
            }
        }
        error("No optional plugin activation request codes are available")
    }

    private companion object {
        const val REQUEST_CODE_START = 52000
        const val REQUEST_CODE_END = 52999
        const val REQUEST_CODE_COUNT = REQUEST_CODE_END - REQUEST_CODE_START + 1
    }
}
