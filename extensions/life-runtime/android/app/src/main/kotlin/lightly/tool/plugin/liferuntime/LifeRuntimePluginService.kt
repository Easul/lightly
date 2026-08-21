package lightly.tool.plugin.liferuntime

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.net.wifi.WifiManager
import android.util.Log
import lightly.tool.plugin.liferuntime.ipc.ILifeRuntimePluginService

class LifeRuntimePluginService : Service() {
    private lateinit var controller: LifeRuntimeController
    private var wifiLock: WifiManager.WifiLock? = null

    private val binder = object : ILifeRuntimePluginService.Stub() {
        override fun getApiVersion(): Int = API_VERSION

        override fun start(serviceId: String, optionsJson: String): String {
            val result = controller.start(serviceId, optionsJson)
            if (controller.hasRunningProcess()) startRuntimeForeground()
            updateWifiLock()
            return result
        }

        override fun stop(serviceId: String): Boolean {
            val stopped = controller.stop(serviceId)
            if (!controller.hasRunningProcess()) stopRuntimeForeground()
            updateWifiLock()
            return stopped
        }

        override fun getStatus(): String = controller.status()

        override fun readConfigFiles(): String = controller.readConfigFiles()

        override fun writeConfigFiles(hostConfigJson: String): String =
            controller.writeConfigFiles(hostConfigJson)

        override fun stopAll() {
            controller.stopAll()
            stopRuntimeForeground()
            updateWifiLock()
        }

        override fun exportData(
            destination: ParcelFileDescriptor,
            hostConfigJson: String,
        ): String = controller.exportData(destination, hostConfigJson)

        override fun importData(source: ParcelFileDescriptor): String = controller.importData(source)
    }

    override fun onCreate() {
        super.onCreate()
        controller = LifeRuntimeController(applicationContext)
        wifiLock = runCatching {
            val manager = getSystemService(WIFI_SERVICE) as? WifiManager
                ?: return@runCatching null
            manager.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "lightly:life-runtime",
            ).apply { setReferenceCounted(false) }
        }.onFailure { error ->
            Log.w(TAG, "Unable to create Life Runtime Wi-Fi lock", error)
        }.getOrNull()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onUnbind(intent: Intent?): Boolean {
        // Keep user-started services alive while Lightly reconnects its Binder.
        return true
    }

    override fun onRebind(intent: Intent?) = Unit

    override fun onDestroy() {
        controller.stopAll()
        releaseWifiLock()
        super.onDestroy()
    }

    private fun updateWifiLock() {
        val lock = wifiLock ?: return
        if (controller.hasLanBoundProcess()) {
            if (!lock.isHeld) {
                runCatching { lock.acquire() }
                    .onFailure { error ->
                        Log.w(TAG, "Unable to acquire Life Runtime Wi-Fi lock", error)
                    }
            }
        } else {
            releaseWifiLock()
        }
    }

    private fun releaseWifiLock() {
        runCatching {
            wifiLock?.takeIf { it.isHeld }?.release()
        }.onFailure { error ->
            Log.w(TAG, "Unable to release Life Runtime Wi-Fi lock", error)
        }
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
        private const val TAG = "LifeRuntimePluginService"
        private const val API_VERSION = 3
        private const val NOTIFICATION_ID = 14611
        private const val NOTIFICATION_CHANNEL = "lightly_life_runtime"
    }
}
