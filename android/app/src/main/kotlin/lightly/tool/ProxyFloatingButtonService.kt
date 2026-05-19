package lightly.tool

import android.annotation.SuppressLint
import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.ImageView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class ProxyFloatingButtonService : Service() {
    private var windowManager: WindowManager? = null
    private var floatingView: ImageView? = null
    private var params: WindowManager.LayoutParams? = null
    private var methodChannel: MethodChannel? = null

    private val buttonSizeDp = 40
    private val buttonAlpha = 128

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate() {
        super.onCreate()

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val density = resources.displayMetrics.density
        val buttonSizePx = (buttonSizeDp * density).toInt()

        floatingView = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher_round)
            imageAlpha = buttonAlpha
            setPadding(4, 4, 4, 4)
            elevation = 8f
        }

        params = WindowManager.LayoutParams(
            buttonSizePx,
            buttonSizePx,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 20
            y = 200
        }

        setupTouchListener()
        windowManager?.addView(floatingView, params)
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun setupTouchListener() {
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false

        floatingView?.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params?.x ?: 0
                    initialY = params?.y ?: 0
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (dx * dx + dy * dy > 25) {
                        isDragging = true
                    }
                    if (isDragging) {
                        params?.x = initialX + dx.toInt()
                        params?.y = initialY + dy.toInt()
                        windowManager?.updateViewLayout(floatingView, params)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!isDragging) {
                        // Tap while visible → notify Flutter
                        notifyFlutterTap()
                        true
                    } else {
                        true
                    }
                }
                else -> false
            }
        }
    }

    private fun notifyFlutterTap() {
        try {
            val engine = FlutterEngine(this)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
            )
            methodChannel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                "lightly.tool/floating_button",
            )
            methodChannel?.invokeMethod("onTap", null)
        } catch (_: Exception) {
            // Flutter engine may not be available
        }
    }

    override fun onDestroy() {
        floatingView?.let {
            windowManager?.removeView(it)
        }
        floatingView = null
        methodChannel = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
