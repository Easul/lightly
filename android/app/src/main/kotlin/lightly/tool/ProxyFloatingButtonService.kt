package lightly.tool

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import androidx.core.app.NotificationCompat

class ProxyFloatingButtonService : Service() {
    companion object {
        private const val CHANNEL_ID = "proxy_floating_button"
        private const val NOTIFICATION_ID = 1202
        private const val BUTTON_ALPHA = 128
        private const val BUTTON_SIZE_DP = 40
        private const val TOUCH_SLOP_DP = 8
    }

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var initialX = 0
    private var initialY = 0
    private var touchX = 0f
    private var touchY = 0f
    private var downX = 0f
    private var downY = 0f

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }

        createNotificationChannel()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    createNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, createNotification())
            }
        } catch (_: RuntimeException) {
            // A device policy can reject the foreground-service promotion. Do not
            // let that exception terminate the host Flutter process.
            stopSelf()
            return START_NOT_STICKY
        }

        if (floatingView == null) {
            showFloatingButton()
        }

        return START_STICKY
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showFloatingButton() {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val metrics = resources.displayMetrics
        val windowType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val size = dpToPx(BUTTON_SIZE_DP)
        val margin = dpToPx(18)

        val params = WindowManager.LayoutParams(
            size,
            size,
            windowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = metrics.widthPixels - size - margin
        params.y = (metrics.heightPixels * 0.38f).toInt()

        val button = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher_round)
            imageAlpha = BUTTON_ALPHA
            setPadding(dpToPx(3), dpToPx(3), dpToPx(3), dpToPx(3))
            elevation = dpToPx(6).toFloat()
        }

        button.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    downX = event.rawX
                    downY = event.rawY
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    params.x = initialX + (event.rawX - touchX).toInt()
                    params.y = initialY + (event.rawY - touchY).toInt()
                    windowManager?.updateViewLayout(button, params)
                    true
                }

                MotionEvent.ACTION_UP -> {
                    val dx = kotlin.math.abs(event.rawX - downX)
                    val dy = kotlin.math.abs(event.rawY - downY)
                    if (dx < dpToPx(TOUCH_SLOP_DP) && dy < dpToPx(TOUCH_SLOP_DP)) {
                        restoreApp()
                    }
                    true
                }

                else -> false
            }
        }

        floatingView = button
        windowManager?.addView(button, params)
    }

    private fun restoreApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }
        startActivity(intent)
        stopSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Proxy Floating Button",
                NotificationManager.IMPORTANCE_LOW,
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val restoreIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            restoreIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("若轻代理保持运行")
            .setContentText("点击恢复应用，Telegram 可继续使用 SOCKS5")
            .setSmallIcon(android.R.drawable.presence_online)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * resources.displayMetrics.density).toInt()
    }

    override fun onDestroy() {
        floatingView?.let {
            windowManager?.removeView(it)
        }
        floatingView = null
        super.onDestroy()
    }
}
