package lightly.tool

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import org.json.JSONObject

class RemoteControlService(private val context: Context) {
    companion object {
        private const val TAG = "RemoteControlService"
        const val REQUEST_MEDIA_PROJECTION = 1001
    }

    private var screenCapture: ScreenCapture? = null
    private var mediaProjection: MediaProjection? = null
    private val handler = Handler(Looper.getMainLooper())
    
    private var onScreenFrame: ((ByteArray, Boolean) -> Unit)? = null
    private var onConfigFrame: ((ByteArray, ByteArray) -> Unit)? = null

    fun startReceiver(
        controlPort: Int,
        screenPort: Int,
        screenFps: Int,
        screenBitrate: Int,
    ) {
        Log.i(TAG, "startReceiver: control=$controlPort screen=$screenPort")
    }

    fun startController(host: String) {
        Log.i(TAG, "startController: host=$host")
    }

    fun stop() {
        Log.i(TAG, "stop")
        stopScreenCapture()
        onScreenFrame = null
        onConfigFrame = null
        handler.removeCallbacksAndMessages(null)
        RemoteControlAccessibilityService.instance?.shutdown()
    }

    fun startScreenCapture(
        activity: Activity,
        fps: Int = 15,
        bitrate: Int = 2_000_000,
        onFrame: (ByteArray, Boolean) -> Unit,
        onConfig: (ByteArray, ByteArray) -> Unit
    ) {
        onScreenFrame = onFrame
        onConfigFrame = onConfig

        val projectionManager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val captureIntent = projectionManager.createScreenCaptureIntent()
        activity.startActivityForResult(captureIntent, REQUEST_MEDIA_PROJECTION)
    }

    fun handleMediaProjectionResult(resultCode: Int, data: Intent?, fps: Int, bitrate: Int) {
        if (resultCode != Activity.RESULT_OK || data == null) {
            Log.e(TAG, "MediaProjection permission denied")
            return
        }

        pendingMediaProjectionResult = resultCode
        pendingMediaProjectionData = data

        startScreenCaptureService()

        handler.postDelayed({
            initMediaProjection(resultCode, data, fps, bitrate)
        }, 500)
    }

    private var pendingMediaProjectionResult: Int = 0
    private var pendingMediaProjectionData: Intent? = null

    private fun initMediaProjection(resultCode: Int, data: Intent?, fps: Int, bitrate: Int) {
        if (data == null) {
            Log.e(TAG, "MediaProjection data is null")
            return
        }

        val projectionManager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = projectionManager.getMediaProjection(resultCode, data)

        if (mediaProjection == null) {
            Log.e(TAG, "Failed to create MediaProjection")
            stopScreenCaptureService()
            return
        }

        val screenInfo = getScreenInfo()
        val width = screenInfo["width"] as Int
        val height = screenInfo["height"] as Int
        val densityDpi = (screenInfo["density"] as Number).toInt()

        screenCapture = ScreenCapture(
            context,
            initialFps = fps,
            initialBitrate = bitrate,
            onFrameEncoded = { data, isKeyFrame ->
                onScreenFrame?.invoke(data, isKeyFrame)
            },
            onConfigFrame = { sps, pps ->
                onConfigFrame?.invoke(sps, pps)
            }
        )

        try {
            screenCapture!!.start(mediaProjection!!, width, height, densityDpi)
            Log.i(TAG, "Screen capture started: ${width}x${height} @ ${fps}fps")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start screen capture", e)
            stopScreenCapture()
        }
    }

    fun stopScreenCapture() {
        Log.i(TAG, "stopScreenCapture: hasCapture=${screenCapture != null} hasProjection=${mediaProjection != null}")
        screenCapture?.stop()
        screenCapture = null
        mediaProjection?.stop()
        mediaProjection = null
        pendingMediaProjectionResult = 0
        pendingMediaProjectionData = null
        stopScreenCaptureService()
    }

    fun requestKeyFrame() {
        Log.i(TAG, "requestKeyFrame: hasCapture=${screenCapture != null} hasProjection=${mediaProjection != null}")
        screenCapture?.requestKeyFrame()
    }

    fun updateBitrate(bitrate: Int) {
        Log.i(TAG, "updateBitrate: bitrate=$bitrate hasCapture=${screenCapture != null}")
        screenCapture?.updateBitrate(bitrate)
    }

    fun executeCommand(commandJson: String) {
        try {
            val command = JSONObject(commandJson)
            val type = command.optString("type")

            when (type) {
                "gesture" -> executeGesture(command)
                "keyboard" -> executeKeyboard(command)
                "global" -> executeGlobal(command)
                "status" -> executeStatus(command)
                else -> Log.w(TAG, "Unknown command type: $type")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to execute command: $e", e)
        }
    }

    private fun executeGesture(command: JSONObject) {
        val service = RemoteControlAccessibilityService.instance
        if (service == null) {
            Log.w(TAG, "AccessibilityService not running")
            return
        }

        val action = command.optString("action")
        val data = command.optJSONObject("data") ?: return

        when (action) {
            "tap" -> {
                val x = data.optDouble("x").toFloat()
                val y = data.optDouble("y").toFloat()
                val duration = data.optLong("duration", 100)
                service.performTap(x, y, duration)
            }
            "swipe" -> {
                val startX = data.optDouble("startX").toFloat()
                val startY = data.optDouble("startY").toFloat()
                val endX = data.optDouble("endX").toFloat()
                val endY = data.optDouble("endY").toFloat()
                val duration = data.optLong("duration", 300)
                service.performSwipe(startX, startY, endX, endY, duration)
            }
            "trajectory" -> {
                val pointsJson = data.optJSONArray("points")
                val points = mutableListOf<Pair<Float, Float>>()
                if (pointsJson != null) {
                    for (index in 0 until pointsJson.length()) {
                        val point = pointsJson.optJSONObject(index) ?: continue
                        points.add(
                            point.optDouble("x").toFloat() to
                                point.optDouble("y").toFloat(),
                        )
                    }
                }
                val duration = data.optLong("duration", 300)
                service.performTrajectory(points, duration)
            }
            "longPress", "long_press" -> {
                val x = data.optDouble("x").toFloat()
                val y = data.optDouble("y").toFloat()
                val duration = data.optLong("duration", 800)
                service.performLongPress(x, y, duration)
            }
            "pinch" -> {
                val centerX = data.optDouble("centerX").toFloat()
                val centerY = data.optDouble("centerY").toFloat()
                val scale = data.optDouble("scale").toFloat()
                val duration = data.optLong("duration", 200)
                service.performPinch(centerX, centerY, scale, duration)
            }
            else -> Log.w(TAG, "Unknown gesture action: $action")
        }
    }

    private fun executeKeyboard(command: JSONObject) {
        val service = RemoteControlAccessibilityService.instance
        if (service == null) {
            Log.w(TAG, "AccessibilityService not running")
            return
        }

        val action = command.optString("action")
        val data = command.optJSONObject("data")

        when (action) {
            "text" -> {
                val text = data?.optString("text").orEmpty()
                if (text.isNotEmpty()) {
                    service.commitText(text)
                }
            }
            "key" -> {
                val keyCode = data?.optInt("keyCode", -1) ?: -1
                if (keyCode >= 0) {
                    service.sendKey(keyCode)
                }
            }
            else -> Log.w(TAG, "Unknown keyboard action: $action")
        }
    }

    private fun executeGlobal(command: JSONObject) {
        val service = RemoteControlAccessibilityService.instance
        if (service == null) {
            Log.w(TAG, "AccessibilityService not running")
            return
        }

        val action = command.optString("action")
        when (action) {
            "back" -> service.performGlobalActionById(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
            "home" -> service.performGlobalActionById(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME)
            "recents" -> service.performGlobalActionById(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_RECENTS)
            else -> Log.w(TAG, "Unknown global action: $action")
        }
    }

    private fun executeStatus(command: JSONObject) {
        val action = command.optString("action")
        val data = command.optJSONObject("data")
        when (action) {
            "overlay_text" -> {
                val text = data?.optString("text").orEmpty()
                if (text.isNotBlank()) {
                    RemoteControlAccessibilityService.instance?.showTextOverlay(text)
                }
            }
            "wake_screen" -> wakeScreen()
            else -> Log.w(TAG, "Unknown status action: $action")
        }
    }

    private fun wakeScreen() {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (powerManager == null) {
            Log.w(TAG, "PowerManager unavailable for wakeScreen")
            return
        }
        @Suppress("DEPRECATION")
        val wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
            "$TAG:wakeScreen",
        )
        try {
            wakeLock.acquire(1800L)
            Log.d(TAG, "wakeScreen requested")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to wake screen", e)
        }
    }

    fun getScreenInfo(): Map<String, Any> {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
        val info = mutableMapOf<String, Any>(
            "width" to metrics.widthPixels,
            "height" to metrics.heightPixels,
            "density" to metrics.densityDpi,
        )
        screenCapture?.getCaptureInfo()?.let { captureInfo ->
            info.putAll(captureInfo)
        }
        return info
    }

    private fun startScreenCaptureService() {
        val intent = Intent(context, RemoteControlScreenCaptureService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun stopScreenCaptureService() {
        val intent = Intent(context, RemoteControlScreenCaptureService::class.java)
        context.stopService(intent)
    }
}
