package lightly.tool.plugin.liferuntime

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import lightly.tool.plugin.liferuntime.ipc.ILifeRuntimePluginService

class LifeRuntimePluginService : Service() {
    private lateinit var controller: LifeRuntimeController

    private val binder = object : ILifeRuntimePluginService.Stub() {
        override fun getApiVersion(): Int = API_VERSION

        override fun start(serviceId: String, optionsJson: String): String {
            val result = controller.start(serviceId, optionsJson)
            if (controller.hasRunningProcess()) startRuntimeForeground()
            return result
        }

        override fun stop(serviceId: String): Boolean {
            val stopped = controller.stop(serviceId)
            if (!controller.hasRunningProcess()) stopRuntimeForeground()
            return stopped
        }

        override fun getStatus(): String = controller.status()

        override fun stopAll() {
            controller.stopAll()
            stopRuntimeForeground()
        }
    }

    override fun onCreate() {
        super.onCreate()
        controller = LifeRuntimeController(applicationContext)
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onUnbind(intent: Intent?): Boolean {
        // The runtime is subordinate to Lightly's binding. A future explicit background
        // ownership feature must introduce a separate user-visible lifecycle contract.
        controller.stopAll()
        stopRuntimeForeground()
        return false
    }

    override fun onDestroy() {
        controller.stopAll()
        super.onDestroy()
    }

    private fun startRuntimeForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "人生知识库运行时",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val launchIntent = packageManager.getLaunchIntentForPackage("lightly.tool")
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }.setContentTitle("Lightly 人生运行时正在运行")
            .setContentText("MindGit / Life Record 服务已启动")
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopRuntimeForeground() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    companion object {
        private const val API_VERSION = 1
        private const val NOTIFICATION_ID = 14611
        private const val NOTIFICATION_CHANNEL = "lightly_life_runtime"
    }
}
