package lightly.tool.plugin.webrtc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.RemoteCallbackList
import android.os.SystemClock
import lightly.tool.plugin.webrtc.ipc.IWebRtcVoicePluginCallback
import lightly.tool.plugin.webrtc.ipc.IWebRtcVoicePluginService
import org.json.JSONObject

class WebRtcVoicePluginService : Service() {
    private val callbacks = object : RemoteCallbackList<IWebRtcVoicePluginCallback>() {
        override fun onCallbackDied(callback: IWebRtcVoicePluginCallback?) {
            if (::worker.isInitialized) {
                worker.post {
                    session.close()
                    stopVoiceForeground()
                    stopSelf()
                }
            }
        }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val foregroundLock = Object()
    @Volatile private var foregroundActive = false
    @Volatile private var foregroundFailure: String? = null
    private lateinit var workerThread: HandlerThread
    private lateinit var worker: Handler
    private lateinit var session: WebRtcVoiceSession

    private val binder = object : IWebRtcVoicePluginService.Stub() {
        override fun getApiVersion(): Int = API_VERSION

        override fun registerCallback(callback: IWebRtcVoicePluginCallback) {
            callbacks.register(callback)
        }

        override fun unregisterCallback(callback: IWebRtcVoicePluginCallback) {
            callbacks.unregister(callback)
        }

        override fun request(requestJson: String) {
            if (requestJson.length > MAX_JSON_LENGTH) {
                return
            }
            worker.post { handleRequest(requestJson) }
        }
    }

    override fun onCreate() {
        super.onCreate()
        workerThread = HandlerThread("LightlyWebRtcVoice")
        workerThread.start()
        worker = Handler(workerThread.looper)
        session = WebRtcVoiceSession(applicationContext, worker, ::broadcast)
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_START_VOICE_FOREGROUND) {
            runCatching { startVoiceForeground() }
                .onFailure {
                    foregroundFailure = it.message ?: it.javaClass.simpleName
                    synchronized(foregroundLock) { foregroundLock.notifyAll() }
                    stopSelf(startId)
                }
        }
        // A killed voice session must not be silently resurrected.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        worker.post { session.close() }
        stopVoiceForeground()
        workerThread.quitSafely()
        callbacks.kill()
        super.onDestroy()
    }

    private fun handleRequest(raw: String) {
        val request = runCatching { JSONObject(raw) }.getOrElse {
            broadcastError(null, "无效的 WebRTC 插件请求")
            return
        }
        val requestId = request.optString("requestId").takeIf { it.isNotBlank() }
        val type = request.optString("type")
        when (type) {
            "prepare" -> {
                val foregroundError = awaitVoiceForeground()
                if (foregroundError != null) {
                    broadcastError(requestId, foregroundError)
                } else {
                    session.prepare(request.optBoolean("isController")) { result ->
                        if (result.isFailure) stopVoiceForeground()
                        complete(requestId, result)
                    }
                }
            }
            "setLocalAudioEnabled" -> complete(
                requestId,
                session.setLocalAudioEnabled(request.optBoolean("enabled")),
            )
            "handleSignal" -> session.handleSignal(
                request.optString("action"),
                request.optJSONObject("data") ?: JSONObject(),
            ) { complete(requestId, it) }
            "getState" -> broadcastResult(requestId, session.stateJson())
            "close" -> {
                session.close()
                stopVoiceForeground()
                broadcastResult(requestId)
            }
            else -> broadcastError(requestId, "未知 WebRTC 插件请求：$type")
        }
    }

    private fun complete(requestId: String?, result: Result<Unit>) {
        result.onSuccess { broadcastResult(requestId) }
            .onFailure { broadcastError(requestId, it.message ?: "WebRTC 插件操作失败") }
    }

    private fun broadcastResult(requestId: String?, data: JSONObject = JSONObject()) {
        broadcast(
            JSONObject()
                .put("type", "result")
                .put("requestId", requestId)
                .put("data", data),
        )
    }

    private fun broadcastError(requestId: String?, message: String) {
        broadcast(
            JSONObject()
                .put("type", "error")
                .put("requestId", requestId)
                .put("message", message.take(MAX_ERROR_LENGTH)),
        )
    }

    private fun broadcast(event: JSONObject) {
        val raw = event.toString()
        if (raw.length > MAX_JSON_LENGTH) {
            return
        }
        val count = callbacks.beginBroadcast()
        try {
            repeat(count) { index ->
                runCatching { callbacks.getBroadcastItem(index).onEvent(raw) }
            }
        } finally {
            callbacks.finishBroadcast()
        }
    }

    private fun startVoiceForeground() {
        if (foregroundActive) return
        foregroundFailure = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "Lightly 远程语音",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val launchIntent = packageManager.getLaunchIntentForPackage(HOST_PACKAGE)
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
        }.setContentTitle("Lightly 远程语音进行中")
            .setContentText("正在使用麦克风进行实时通话")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        foregroundActive = true
        synchronized(foregroundLock) { foregroundLock.notifyAll() }
    }

    private fun awaitVoiceForeground(): String? {
        val deadline = SystemClock.elapsedRealtime() + FOREGROUND_READY_TIMEOUT_MS
        synchronized(foregroundLock) {
            while (!foregroundActive) {
                val remaining = deadline - SystemClock.elapsedRealtime()
                if (remaining <= 0) break
                foregroundLock.wait(remaining)
            }
        }
        if (foregroundActive) return null
        val detail = foregroundFailure?.takeIf { it.isNotBlank() }
        return if (detail == null) {
            "远程语音前台服务未就绪，请重试"
        } else {
            "远程语音前台服务启动失败：$detail"
        }
    }

    private fun stopVoiceForeground() {
        foregroundActive = false
        synchronized(foregroundLock) { foregroundLock.notifyAll() }
        mainHandler.post {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }

    companion object {
        const val ACTION_START_VOICE_FOREGROUND =
            "lightly.tool.plugin.webrtc.START_VOICE_FOREGROUND"
        private const val API_VERSION = 3
        private const val MAX_JSON_LENGTH = 512 * 1024
        private const val MAX_ERROR_LENGTH = 512
        private const val FOREGROUND_READY_TIMEOUT_MS = 2_000L
        private const val NOTIFICATION_ID = 14603
        private const val NOTIFICATION_CHANNEL = "lightly_webrtc_voice"
        private const val HOST_PACKAGE = "lightly.tool"
    }
}
