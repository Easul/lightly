package lightly.tool

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.roundToInt

class TranslationOverlayService : Service() {
    companion object {
        private const val CHANNEL_ID = "translation_overlay"
        private const val NOTIFICATION_ID = 1205
        private const val ACTION_STOP = "lightly.tool.action.STOP_TRANSLATION_OVERLAY"
        private const val CONFIG_KEY = "config"

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context, config: Map<String, Any?>) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, TranslationOverlayService::class.java).apply {
                    putExtra(CONFIG_KEY, JSONObject(config).toString())
                },
            )
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var historyStore: TranslationHistoryStore
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var config: TranslationApiConfig? = null

    override fun onCreate() {
        super.onCreate()
        historyStore = TranslationHistoryStore(this)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        updateConfig(intent?.getStringExtra(CONFIG_KEY))
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        if (overlayView == null) showOverlay()
        isRunning = true
        return START_STICKY
    }

    private fun updateConfig(rawConfig: String?) {
        val preferences = getSharedPreferences("translation_overlay", MODE_PRIVATE)
        if (rawConfig != null) {
            preferences.edit().putString(CONFIG_KEY, rawConfig).apply()
        }
        val raw = rawConfig ?: preferences.getString(CONFIG_KEY, null) ?: return
        config = try {
            val json = JSONObject(raw)
            TranslationApiConfig(
                baseUrl = json.optString("baseUrl"),
                apiKey = json.optString("apiKey"),
                model = json.optString("model"),
                endpoint = json.optString("endpoint", "openAiResponses"),
            )
        } catch (_: Exception) {
            null
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showOverlay() {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(8), dp(10), dp(10))
            background = roundedBackground(0xF7FFFFFF.toInt(), 0x335F6F65, 12)
            elevation = dp(6).toFloat()
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val title = TextView(this).apply {
            text = "悬浮翻译"
            setTextColor(0xFF313733.toInt())
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, dp(32), 1f)
        }
        val closeButton = TextView(this).apply {
            text = "×"
            textSize = 22f
            gravity = Gravity.CENTER
            setTextColor(0xFF5F6862.toInt())
            setOnClickListener { stopSelf() }
        }
        val resizeButton = TextView(this).apply {
            text = "↔"
            textSize = 18f
            gravity = Gravity.CENTER
            contentDescription = "调整悬浮翻译大小"
            setTextColor(0xFF5F6862.toInt())
        }
        val collapseButton = TextView(this).apply {
            text = "—"
            textSize = 18f
            gravity = Gravity.CENTER
            contentDescription = "收起悬浮翻译"
            setTextColor(0xFF5F6862.toInt())
        }
        header.addView(title)
        header.addView(resizeButton, LinearLayout.LayoutParams(dp(36), dp(32)))
        header.addView(collapseButton, LinearLayout.LayoutParams(dp(36), dp(32)))
        header.addView(closeButton, LinearLayout.LayoutParams(dp(36), dp(32)))

        val input = EditText(this).apply {
            hint = "输入中文或英文"
            textSize = 14f
            minLines = 2
            maxLines = 5
            setTextColor(0xFF222724.toInt())
            setHintTextColor(0xFF8A928D.toInt())
            background = roundedBackground(0xFFF3F6F4.toInt(), 0x225F6F65, 9)
            setPadding(dp(9), dp(7), dp(9), dp(7))
        }
        val output = TextView(this).apply {
            text = "译文会显示在这里"
            textSize = 14f
            setTextColor(0xFF313733.toInt())
            setTextIsSelectable(true)
            minHeight = dp(46)
            setPadding(dp(9), dp(8), dp(9), dp(8))
            background = roundedBackground(0xFFF7F8F7.toInt(), 0x225F6F65, 9)
        }
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        val copyButton = Button(this).apply {
            text = "复制"
            textSize = 12f
            isAllCaps = false
            setOnClickListener {
                val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("translation", output.text))
            }
        }
        val translateButton = Button(this).apply {
            text = "翻译"
            textSize = 12f
            isAllCaps = false
        }
        actions.addView(copyButton, LinearLayout.LayoutParams(dp(76), dp(42)))
        actions.addView(translateButton, LinearLayout.LayoutParams(dp(84), dp(42)))
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(input, LinearLayout.LayoutParams(dp(292), LinearLayout.LayoutParams.WRAP_CONTENT))
            addView(View(this@TranslationOverlayService), LinearLayout.LayoutParams(1, dp(7)))
            addView(output, LinearLayout.LayoutParams(dp(292), LinearLayout.LayoutParams.WRAP_CONTENT))
            addView(actions)
        }
        panel.addView(header)
        panel.addView(content)

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
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(12)
            y = dp(110)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
        }
        val scaleLevels = floatArrayOf(0.82f, 1f, 1.18f)
        var scaleIndex = 0
        var collapsed = false

        fun scaled(value: Int): Int = dp((value * scaleLevels[scaleIndex]).roundToInt())

        fun keepInsideScreen() {
            val maxX = (resources.displayMetrics.widthPixels - panel.width).coerceAtLeast(0)
            val maxY = (resources.displayMetrics.heightPixels - panel.height).coerceAtLeast(0)
            params.x = params.x.coerceIn(0, maxX)
            params.y = params.y.coerceIn(0, maxY)
        }

        fun setWindowFocusable(focusable: Boolean) {
            params.flags = if (focusable) {
                params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            } else {
                params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            }
            if (!focusable) {
                input.clearFocus()
                (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
                    .hideSoftInputFromWindow(input.windowToken, 0)
            }
            windowManager?.updateViewLayout(panel, params)
        }

        fun applyScale() {
            val scale = scaleLevels[scaleIndex]
            panel.setPadding(scaled(10), scaled(8), scaled(10), scaled(10))
            title.textSize = 13f * scale
            resizeButton.textSize = 18f * scale
            collapseButton.textSize = 18f * scale
            closeButton.textSize = 22f * scale
            input.textSize = 14f * scale
            output.textSize = 14f * scale
            copyButton.textSize = 12f * scale
            translateButton.textSize = 12f * scale
            header.layoutParams = LinearLayout.LayoutParams(
                scaled(292),
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            title.layoutParams = LinearLayout.LayoutParams(0, scaled(32), 1f)
            resizeButton.layoutParams = LinearLayout.LayoutParams(scaled(36), scaled(32))
            collapseButton.layoutParams = LinearLayout.LayoutParams(scaled(36), scaled(32))
            closeButton.layoutParams = LinearLayout.LayoutParams(scaled(36), scaled(32))
            input.layoutParams = LinearLayout.LayoutParams(
                scaled(292),
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            output.layoutParams = LinearLayout.LayoutParams(
                scaled(292),
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            input.setPadding(scaled(9), scaled(7), scaled(9), scaled(7))
            output.setPadding(scaled(9), scaled(8), scaled(9), scaled(8))
            output.minHeight = scaled(46)
            copyButton.layoutParams = LinearLayout.LayoutParams(scaled(76), scaled(42))
            translateButton.layoutParams = LinearLayout.LayoutParams(scaled(84), scaled(42))
            panel.requestLayout()
            panel.post {
                keepInsideScreen()
                windowManager?.updateViewLayout(panel, params)
            }
        }

        fun applyCollapsedState() {
            if (collapsed) {
                content.visibility = View.GONE
                title.visibility = View.GONE
                resizeButton.visibility = View.GONE
                closeButton.visibility = View.GONE
                collapseButton.text = "译"
                collapseButton.contentDescription = "展开悬浮翻译"
                collapseButton.layoutParams = LinearLayout.LayoutParams(scaled(48), scaled(48))
                header.layoutParams = LinearLayout.LayoutParams(scaled(48), scaled(48))
                header.gravity = Gravity.CENTER
                panel.setPadding(0, 0, 0, 0)
                panel.background = roundedBackground(0xF25F7567.toInt(), 0x55FFFFFF, 999)
                collapseButton.setTextColor(0xFFFFFFFF.toInt())
            } else {
                content.visibility = View.VISIBLE
                title.visibility = View.VISIBLE
                resizeButton.visibility = View.VISIBLE
                closeButton.visibility = View.VISIBLE
                collapseButton.text = "—"
                collapseButton.contentDescription = "收起悬浮翻译"
                header.layoutParams = LinearLayout.LayoutParams(
                    scaled(292),
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                )
                header.gravity = Gravity.CENTER_VERTICAL
                panel.background = roundedBackground(0xF7FFFFFF.toInt(), 0x335F6F65, 12)
                collapseButton.setTextColor(0xFF5F6862.toInt())
                applyScale()
            }
            panel.requestLayout()
            panel.post {
                keepInsideScreen()
                windowManager?.updateViewLayout(panel, params)
            }
        }

        attachDrag(header, panel, params)
        resizeButton.setOnClickListener {
            scaleIndex = (scaleIndex + 1) % scaleLevels.size
            applyScale()
        }
        collapseButton.setOnClickListener {
            setWindowFocusable(false)
            collapsed = !collapsed
            applyCollapsedState()
        }
        var collapsedTouchX = 0f
        var collapsedTouchY = 0f
        var collapsedInitialX = 0
        var collapsedInitialY = 0
        var collapsedMoved = false
        collapseButton.setOnTouchListener { _, event ->
            if (!collapsed) return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    collapsedTouchX = event.rawX
                    collapsedTouchY = event.rawY
                    collapsedInitialX = params.x
                    collapsedInitialY = params.y
                    collapsedMoved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = event.rawX - collapsedTouchX
                    val deltaY = event.rawY - collapsedTouchY
                    if (abs(deltaX) > dp(4) || abs(deltaY) > dp(4)) collapsedMoved = true
                    val maxX = (resources.displayMetrics.widthPixels - panel.width).coerceAtLeast(0)
                    val maxY = (resources.displayMetrics.heightPixels - panel.height).coerceAtLeast(0)
                    params.x = (collapsedInitialX + deltaX.toInt()).coerceIn(0, maxX)
                    params.y = (collapsedInitialY + deltaY.toInt()).coerceIn(0, maxY)
                    windowManager?.updateViewLayout(panel, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!collapsedMoved) {
                        collapsed = false
                        applyCollapsedState()
                    }
                    true
                }
                else -> true
            }
        }
        input.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_DOWN &&
                params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE != 0
            ) {
                setWindowFocusable(true)
                input.post {
                    input.requestFocus()
                    (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
                        .showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
                }
            }
            false
        }
        panel.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_OUTSIDE) {
                setWindowFocusable(false)
            }
            false
        }
        translateButton.setOnClickListener {
            setWindowFocusable(false)
            translate(input, output, translateButton)
        }
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        overlayView = panel
        windowManager?.addView(panel, params)
        applyScale()
    }

    private fun translate(input: EditText, output: TextView, button: Button) {
        val source = input.text.toString().trim()
        val currentConfig = config
        if (source.isEmpty()) return
        if (currentConfig == null || currentConfig.baseUrl.isBlank() || currentConfig.model.isBlank()) {
            output.text = "请先在应用内完成 AI 接口设置"
            return
        }
        button.isEnabled = false
        output.text = "翻译中…"
        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
            .hideSoftInputFromWindow(input.windowToken, 0)
        thread(name = "translation-overlay-request") {
            try {
                val translated = TranslationApiClient().translate(currentConfig, source)
                historyStore.save(
                    mapOf(
                        "id" to System.nanoTime().toString(),
                        "source" to source,
                        "translation" to translated,
                        "targetLanguage" to "自动",
                        "createdAt" to System.currentTimeMillis(),
                    ),
                )
                mainHandler.post { output.text = translated }
            } catch (error: Exception) {
                mainHandler.post { output.text = error.message ?: "翻译失败" }
            } finally {
                mainHandler.post { button.isEnabled = true }
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun attachDrag(dragView: View, panel: View, params: WindowManager.LayoutParams) {
        var initialX = 0
        var initialY = 0
        var touchX = 0f
        var touchY = 0f
        dragView.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val maxX = (resources.displayMetrics.widthPixels - panel.width).coerceAtLeast(0)
                    val maxY = (resources.displayMetrics.heightPixels - panel.height).coerceAtLeast(0)
                    params.x = (initialX + (event.rawX - touchX).toInt()).coerceIn(0, maxX)
                    params.y = (initialY + (event.rawY - touchY).toInt()).coerceIn(0, maxY)
                    windowManager?.updateViewLayout(panel, params)
                    true
                }
                else -> false
            }
        }
    }

    private fun roundedBackground(color: Int, stroke: Int, radius: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radius).toFloat()
        setStroke(dp(1), stroke)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "悬浮翻译",
                NotificationManager.IMPORTANCE_LOW,
            )
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val stopIntent = Intent(this, TranslationOverlayService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_set_as)
            .setContentTitle("悬浮翻译运行中")
            .setContentText("中文与英文自动互译")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(0, "关闭", stopPendingIntent)
            .build()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        overlayView?.let { windowManager?.removeView(it) }
        overlayView = null
        isRunning = false
        super.onDestroy()
    }
}
