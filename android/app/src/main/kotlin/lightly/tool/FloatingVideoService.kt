package lightly.tool

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.FlutterInjector

class FloatingVideoService : Service() {
    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var flutterEngine: FlutterEngine? = null
    private val channelName = "floating_video"
    private var initialX = 0
    private var initialY = 0
    private var touchX = 0f
    private var touchY = 0f
    private var isExpanded = false
    private var screenWidth = 0
    private var screenHeight = 0
    private var statusBarHeight = 0

    override fun onCreate() {
        super.onCreate()
        FlutterInjector.instance().flutterLoader().startInitialization(applicationContext)
        FlutterInjector.instance().flutterLoader().ensureInitializationComplete(applicationContext, arrayOf())
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val videoUrl = intent?.getStringExtra("videoUrl") ?: return START_NOT_STICKY
        val title = intent.getStringExtra("title") ?: "视频播放"

        showFloatingWindow(videoUrl, title)
        return START_NOT_STICKY
    }

    private fun showFloatingWindow(videoUrl: String, title: String) {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val metrics = resources.displayMetrics
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
        statusBarHeight = getStatusBarHeight()

        val windowType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
        
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            windowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )

        params.gravity = Gravity.TOP or Gravity.START
        params.x = 0
        params.y = statusBarHeight + dpToPx(56)
        params.width = screenWidth
        params.height = dpToPx(200)

        flutterEngine = FlutterEngineCache.getInstance().get("floating_video_engine")
        if (flutterEngine == null) {
            flutterEngine = FlutterEngine(applicationContext)
            FlutterEngineCache.getInstance().put("floating_video_engine", flutterEngine!!)
        }

        flutterEngine!!.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )

        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVideoUrl" -> result.success(videoUrl)
                    "getTitle" -> result.success(title)
                    "toggleExpand" -> {
                        isExpanded = !isExpanded
                        updateWindowSize(params)
                        result.success(isExpanded)
                    }
                    "isExpanded" -> result.success(isExpanded)
                    "close" -> {
                        stopSelf()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        val flutterView = FlutterView(applicationContext)
        flutterView.attachToFlutterEngine(flutterEngine!!)

        val container = FrameLayout(applicationContext)
        container.addView(flutterView)

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!isExpanded) {
                        params.x = initialX + (event.rawX - touchX).toInt()
                        params.y = initialY + (event.rawY - touchY).toInt()
                        constrainPosition(params)
                        windowManager?.updateViewLayout(container, params)
                    }
                    true
                }
                else -> false
            }
        }

        floatingView = container
        windowManager?.addView(floatingView, params)
    }

    private fun updateWindowSize(params: WindowManager.LayoutParams) {
        if (isExpanded) {
            params.width = screenWidth
            params.height = screenHeight
            params.x = 0
            params.y = 0
        } else {
            params.width = screenWidth
            params.height = dpToPx(200)
            params.x = 0
            params.y = statusBarHeight + dpToPx(56)
            constrainPosition(params)
        }
        floatingView?.let {
            windowManager?.updateViewLayout(it, params)
        }
    }

    private fun constrainPosition(params: WindowManager.LayoutParams) {
        val maxY = screenHeight - params.height - dpToPx(80)
        val minY = statusBarHeight + dpToPx(56)
        params.x = params.x.coerceIn(0, screenWidth - params.width)
        params.y = params.y.coerceIn(minY, maxY)
    }

    private fun getStatusBarHeight(): Int {
        val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else dpToPx(24)
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * resources.displayMetrics.density).toInt()
    }

    override fun onDestroy() {
        super.onDestroy()
        floatingView?.let {
            windowManager?.removeView(it)
        }
        floatingView = null
    }
}
