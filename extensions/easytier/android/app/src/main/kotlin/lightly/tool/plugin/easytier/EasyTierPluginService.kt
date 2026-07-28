package lightly.tool.plugin.easytier

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import lightly.tool.plugin.easytier.ipc.IEasyTierPluginService

class EasyTierPluginService : Service() {
    private lateinit var controller: EasyTierRuntimeController

    private val binder = object : IEasyTierPluginService.Stub() {
        override fun getApiVersion(): Int = API_VERSION
        override fun parseConfig(config: String): Boolean = controller.parseConfig(config)
        override fun hasVpnPermission(): Boolean = controller.hasVpnPermission()

        override fun startNetwork(
            config: String,
            instanceName: String,
            useAndroidVpn: Boolean,
        ): Boolean {
            val started = controller.startNetwork(config, instanceName, useAndroidVpn)
            if (started) startRuntimeForeground()
            return started
        }

        override fun stopNetwork(): Boolean {
            val stopped = controller.stopNetwork()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return stopped
        }

        override fun getNetworkInfo(): String? = controller.getNetworkInfo()
        override fun getLastError(): String? = controller.getLastError()
    }

    override fun onCreate() {
        super.onCreate()
        controller = EasyTierRuntimeController(applicationContext)
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onUnbind(intent: Intent?): Boolean {
        // EasyTier promotes this bound service to a started foreground service while the network
        // is active. Without explicit cleanup, losing Lightly's binding leaves the native runtime
        // and VPN alive after Lightly is removed from recents or its process is killed.
        stopRuntimeAfterHostDisconnect()
        return false
    }

    override fun onDestroy() {
        controller.close()
        super.onDestroy()
    }

    private fun stopRuntimeAfterHostDisconnect() {
        controller.close()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startRuntimeForeground() {
        val selfIntent = Intent(this, EasyTierPluginService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(selfIntent)
        } else {
            startService(selfIntent)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "EasyTier P2P 网络",
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
        }.setContentTitle("Lightly EasyTier 正在运行")
            .setContentText("P2P 网络连接已启用")
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    companion object {
        private const val API_VERSION = 2
        private const val NOTIFICATION_ID = 14602
        private const val NOTIFICATION_CHANNEL = "lightly_easytier_runtime"
    }
}
