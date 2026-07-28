package lightly.tool.plugin.webrtc

import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.RemoteCallbackList
import lightly.tool.plugin.webrtc.ipc.IWebRtcVoicePluginCallback
import lightly.tool.plugin.webrtc.ipc.IWebRtcVoicePluginService
import org.json.JSONObject

class WebRtcVoicePluginService : Service() {
    private val callbacks = object : RemoteCallbackList<IWebRtcVoicePluginCallback>() {
        override fun onCallbackDied(callback: IWebRtcVoicePluginCallback?) {
            if (::worker.isInitialized) {
                worker.post {
                    session.close()
                    stopSelf()
                }
            }
        }
    }
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

    override fun onDestroy() {
        worker.post { session.close() }
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
            "prepare" -> session.prepare(request.optBoolean("isController")) {
                complete(requestId, it)
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

    companion object {
        private const val API_VERSION = 2
        private const val MAX_JSON_LENGTH = 512 * 1024
        private const val MAX_ERROR_LENGTH = 512
    }
}
