package lightly.tool

import android.annotation.SuppressLint
import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
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

    private val handler = Handler(Looper.getMainLooper())

    // Idle state
    private var isIdle = false
    private val idleTimeoutMs = 10_000L
    private val normalSizeDp = 56
    private val idleSizeDp = 28
    private val normalAlpha = 255 // 0-255
    private val idleAlpha = 51    // 20% of 255

    private val idleRunnable = Runnable {
        if (!isIdle) {
            isIdle = true
            updateButtonAppearance()
        }
    }

    private fun resetIdleTimer() {
        handler.removeCallbacks(idleRunnable)
        handler.postDelayed(idleRunnable, idleTimeoutMs)
    }

    private fun exitIdle() {
        if (isIdle) {
            isIdle = false
            updateButtonAppearance()
        }
        resetIdleTimer()
    }

    private fun updateButtonAppearance() {
        floatingView?.let { view ->
            val density = resources.displayMetrics.density
            val sizeDp = if (isIdle) idleSizeDp else normalSizeDp
            val sizePx = (sizeDp * density).toInt()

            view.imageAlpha = if (isIdle) idleAlpha else normalAlpha

            params?.let { p ->
                p.width = sizePx
                p.height = sizePx
                windowManager?.updateViewLayout(view, p)
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate() {
        super.onCreate()

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val density = resources.displayMetrics.density
        val normalSizePx = (normalSizeDp * density).toInt()

        floatingView = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher_round)
            imageAlpha = normalAlpha
            setPadding(4, 4, 4, 4)
            elevation = 8f
        }

        params = WindowManager.LayoutParams(
            normalSizePx,
            normalSizePx,
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

        // Start idle timer
        resetIdleTimer()
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
                    // Any interaction resets idle timer
                    if (isIdle) {
                        exitIdle()
                    } else {
                        resetIdleTimer()
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (isIdle) {
                        // Tap while idle → only restore appearance
                        exitIdle()
                        true
                    } else if (!isDragging) {
                        // Tap while visible → notify Flutter
                        resetIdleTimer()
                        notifyFlutterTap()
                        true
                    } else {
                        resetIdleTimer()
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
        handler.removeCallbacks(idleRunnable)
        floatingView?.let {
            windowManager?.removeView(it)
        }
        floatingView = null
        methodChannel = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
