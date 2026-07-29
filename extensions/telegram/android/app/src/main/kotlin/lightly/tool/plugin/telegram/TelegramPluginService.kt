package lightly.tool.plugin.telegram

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.RemoteCallbackList
import android.util.Log
import lightly.tool.plugin.telegram.ipc.ITelegramPluginCallback
import lightly.tool.plugin.telegram.ipc.ITelegramPluginService
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

class TelegramPluginService : Service() {
    private val callbacks = object : RemoteCallbackList<ITelegramPluginCallback>() {
        override fun onCallbackDied(callback: ITelegramPluginCallback?) {
            stopRuntimeWhenHostIsGone()
        }
    }
    private val clientIds = ConcurrentHashMap.newKeySet<Int>()
    private val receiving = AtomicBoolean(false)
    private val receiverLock = Any()
    private var receiverThread: Thread? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var hostBound = false
    private val stopIfUnbound = Runnable {
        if (!hostBound) stopRuntimeWhenHostIsGone()
    }
    private val requestSanitizer by lazy {
        val root = java.io.File(filesDir, "telegram")
        TelegramRequestSanitizer(
            databaseDirectory = java.io.File(root, "database"),
            filesDirectory = java.io.File(root, "files"),
        )
    }

    private val binder = object : ITelegramPluginService.Stub() {
        override fun getApiVersion(): Int {
            enforceTrustedCaller()
            return API_VERSION
        }

        override fun createClient(): Int {
            enforceTrustedCaller()
            // TDLib queues its initial authorization update until receive() starts. Starting the
            // loop here can race the Binder reply, causing Lightly to discard that update before
            // it has stored the returned client ID.
            return TelegramNativeBridge.createClient().also { clientId ->
                clientIds += clientId
                Log.i(LOG_TAG, "Created TDLib client $clientId")
            }
        }

        override fun send(clientId: Int, requestJson: String) {
            enforceTrustedCaller()
            require(requestJson.length <= MAX_JSON_LENGTH) { "TDLib request is too large" }
            val sanitizedRequest = requestSanitizer.rewrite(requestJson)
            TelegramNativeBridge.send(clientId, sanitizedRequest)
            logLifecycleRequest(sanitizedRequest)
            ensureReceiverStarted()
        }

        override fun execute(requestJson: String): String? {
            enforceTrustedCaller()
            require(requestJson.length <= MAX_JSON_LENGTH) { "TDLib request is too large" }
            return TelegramNativeBridge.execute(requestJson)
        }

        override fun registerCallback(callback: ITelegramPluginCallback) {
            enforceTrustedCaller()
            callbacks.register(callback)
        }

        override fun unregisterCallback(callback: ITelegramPluginCallback) {
            enforceTrustedCaller()
            callbacks.unregister(callback)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_START_FOREGROUND) {
            startRuntimeForeground()
            mainHandler.removeCallbacks(stopIfUnbound)
            mainHandler.postDelayed(stopIfUnbound, HOST_BIND_TIMEOUT_MS)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder {
        enforceTrustedCaller()
        hostBound = true
        mainHandler.removeCallbacks(stopIfUnbound)
        return binder
    }

    override fun onUnbind(intent: Intent?): Boolean {
        hostBound = false
        stopRuntimeWhenHostIsGone()
        return false
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(stopIfUnbound)
        hostBound = false
        closeClients()
        stopReceiver()
        stopForeground(STOP_FOREGROUND_REMOVE)
        callbacks.kill()
        super.onDestroy()
    }

    private fun stopRuntimeWhenHostIsGone() {
        Log.i(LOG_TAG, "Lightly host disconnected; closing TDLib clients")
        closeClients()
        stopReceiver()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startRuntimeForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "Lightly TG 工具",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle("Lightly TG 工具正在运行")
            .setContentText("正在维持 Telegram 会话")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun closeClients() {
        clientIds.forEach { clientId ->
            runCatching { TelegramNativeBridge.send(clientId, CLOSE_REQUEST) }
        }
        clientIds.clear()
    }

    private fun stopReceiver() {
        synchronized(receiverLock) {
            receiving.set(false)
            val thread = receiverThread
            thread?.interrupt()
            if (thread != null && thread !== Thread.currentThread()) {
                runCatching { thread.join(RECEIVER_STOP_TIMEOUT_MS) }
            }
            receiverThread = null
        }
    }

    private fun ensureReceiverStarted() {
        synchronized(receiverLock) {
            if (receiverThread?.isAlive == true) {
                return
            }
            receiving.set(true)
            receiverThread = Thread({ receiveLoop() }, "TelegramTdlibReceiver").apply {
                isDaemon = true
                start()
            }
        }
    }

    private fun receiveLoop() {
        try {
            while (receiving.get()) {
                val result = TelegramNativeBridge.receive(RECEIVE_TIMEOUT_SECONDS) ?: continue
                if (result.length <= MAX_JSON_LENGTH) {
                    logAuthorizationUpdate(result)
                    broadcast(result)
                }
            }
        } finally {
            receiving.set(false)
        }
    }

    private fun logLifecycleRequest(requestJson: String) {
        val type = runCatching { JSONObject(requestJson).optString("@type") }
            .getOrDefault("")
        if (type in LOGGED_REQUEST_TYPES) {
            Log.i(LOG_TAG, "Sent TDLib request $type")
        }
    }

    private fun logAuthorizationUpdate(resultJson: String) {
        val type = runCatching { JSONObject(resultJson).optString("@type") }
            .getOrDefault("")
        if (type == "updateAuthorizationState") {
            Log.i(LOG_TAG, "Received TDLib authorization update")
        }
    }

    private fun broadcast(resultJson: String) {
        val count = callbacks.beginBroadcast()
        try {
            for (index in 0 until count) {
                runCatching { callbacks.getBroadcastItem(index).onResult(resultJson) }
            }
        } finally {
            callbacks.finishBroadcast()
        }
    }

    private fun enforceTrustedCaller() {
        val callerUid = Binder.getCallingUid()
        if (callerUid == applicationInfo.uid) {
            return
        }
        val trusted = packageManager.getPackagesForUid(callerUid).orEmpty().any { packageName ->
            packageManager.checkSignatures(packageName, this.packageName) ==
                PackageManager.SIGNATURE_MATCH
        }
        check(trusted) { "Caller signature does not match Telegram plugin" }
    }

    companion object {
        const val API_VERSION = 3
        const val ACTION_START_FOREGROUND =
            "lightly.tool.plugin.telegram.action.START_FOREGROUND"
        private const val LOG_TAG = "TelegramPlugin"
        private const val MAX_JSON_LENGTH = 512 * 1024
        private const val RECEIVE_TIMEOUT_SECONDS = 0.25
        private const val RECEIVER_STOP_TIMEOUT_MS = 1_000L
        private const val HOST_BIND_TIMEOUT_MS = 10_000L
        private const val NOTIFICATION_ID = 14601
        private const val NOTIFICATION_CHANNEL = "lightly_telegram_runtime"
        private const val CLOSE_REQUEST = "{\"@type\":\"close\"}"
        private val LOGGED_REQUEST_TYPES = setOf(
            "getAuthorizationState",
            "setTdlibParameters",
            "addProxy",
            "disableProxy",
        )
    }
}
