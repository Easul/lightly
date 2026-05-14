package lightly.tool

import android.app.Application
import android.os.Build
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class RuoqingApplication : Application() {
    companion object {
        private const val runtimeLoggingEnabled = false
    }

    override fun onCreate() {
        if (!runtimeLoggingEnabled) {
            super.onCreate()
            return
        }
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            writeCrashLog(thread, throwable)
            previousHandler?.uncaughtException(thread, throwable)
        }
        super.onCreate()
    }

    private fun writeCrashLog(thread: Thread, throwable: Throwable) {
        try {
            val baseDir = getExternalFilesDir(null) ?: filesDir
            val logsDir = File(baseDir, "logs")
            if (!logsDir.exists()) {
                logsDir.mkdirs()
            }
            val logFile = File(logsDir, "runtime.log")
            val stackWriter = StringWriter()
            throwable.printStackTrace(PrintWriter(stackWriter))
            val entry = buildString {
                append("=== ")
                append(SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(Date()))
                appendLine(" ===")
                appendLine("Android uncaught exception")
                appendLine("thread=${thread.name}")
                appendLine("sdk=${Build.VERSION.SDK_INT}")
                appendLine("release=${Build.VERSION.RELEASE}")
                appendLine("device=${Build.MANUFACTURER} ${Build.MODEL}")
                appendLine(stackWriter.toString())
                appendLine()
            }
            logFile.appendText(entry)
        } catch (_: Throwable) {
        }
    }
}
