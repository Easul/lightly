package lightly.tool

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Path
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.util.DisplayMetrics
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 无障碍服务 - 用于注入手势事件
 * 
 * 支持的功能：
 * - 点击 (tap)
 * - 滑动 (swipe)
 * - 长按 (long_press)
 * - 双指缩放 (pinch)
 * - 全局操作 (back, home, recents)
 * 
 * Android 7 (API 24) 兼容性：
 * - dispatchGesture() - API 24+ ✅
 * - StrokeDescription - API 24+ ✅
 * - continueStroke() - API 26+ (Android 7 使用整段路径替代)
 */
class RemoteControlAccessibilityService : AccessibilityService() {
    private data class GesturePoint(
        val x: Float,
        val y: Float,
    )

    
    companion object {
        private const val TAG = "RemoteControlA11y"
        
        var instance: RemoteControlAccessibilityService? = null
            private set
        
        val isRunning: Boolean
            get() = instance != null
    }

    private var textOverlayView: View? = null
    private var disconnectOverlayView: View? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        
        // 配置无障碍服务
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPES_ALL_MASK
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            notificationTimeout = 100
        }
        
        Log.i(TAG, "AccessibilityService connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 不需要处理事件，仅用于注入手势
    }

    override fun onInterrupt() {
        Log.w(TAG, "AccessibilityService interrupted")
    }

    override fun onDestroy() {
        hideTextOverlay()
        hideDisconnectOverlay()
        instance = null
        Log.i(TAG, "AccessibilityService destroyed")
        super.onDestroy()
    }

    fun showTextOverlay(text: String) {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        hideTextOverlay()

        val container = buildGlobalOverlayCard(
            title = "远程文字提示",
            message = text,
            accentColor = Color.rgb(124, 58, 237),
            iconText = "T",
            onClose = { hideTextOverlay() },
        )

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            width = WindowManager.LayoutParams.MATCH_PARENT
            horizontalMargin = 0.06f
            y = dp(18)
        }

        try {
            windowManager.addView(container, params)
            textOverlayView = container
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show text overlay", e)
        }
    }

    fun showDisconnectOverlay(message: String) {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        hideDisconnectOverlay()

        val container = buildGlobalOverlayCard(
            title = "对方已断开",
            message = message,
            accentColor = Color.rgb(220, 38, 38),
            iconText = "!",
            onClose = { hideDisconnectOverlay() },
        )

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            width = WindowManager.LayoutParams.MATCH_PARENT
            horizontalMargin = 0.06f
            y = dp(18)
        }

        try {
            windowManager.addView(container, params)
            disconnectOverlayView = container
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show disconnect overlay", e)
        }
    }

    private fun buildGlobalOverlayCard(
        title: String,
        message: String,
        accentColor: Int,
        iconText: String,
        onClose: () -> Unit,
    ): View {
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(16), dp(18), dp(16))
            background = roundedDrawable(
                color = Color.argb(244, 17, 24, 39),
                radius = dp(26).toFloat(),
                strokeColor = Color.argb(34, 255, 255, 255),
                strokeWidth = dp(1),
            )
            elevation = dp(18).toFloat()
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val icon = TextView(this).apply {
            text = iconText
            setTextColor(Color.WHITE)
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = roundedDrawable(
                color = accentColor,
                radius = dp(15).toFloat(),
            )
        }
        header.addView(
            icon,
            LinearLayout.LayoutParams(dp(40), dp(40)),
        )
        val titleView = TextView(this).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            includeFontPadding = false
        }
        header.addView(
            titleView,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                leftMargin = dp(12)
            },
        )
        val closeButton = Button(this).apply {
            text = "关闭"
            setTextColor(Color.WHITE)
            textSize = 13f
            minHeight = 0
            minWidth = 0
            minimumHeight = 0
            minimumWidth = 0
            setPadding(dp(14), dp(7), dp(14), dp(7))
            background = roundedDrawable(
                color = Color.argb(32, 255, 255, 255),
                radius = dp(999).toFloat(),
                strokeColor = Color.argb(45, 255, 255, 255),
                strokeWidth = dp(1),
            )
            setOnClickListener { onClose() }
        }
        header.addView(
            closeButton,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        container.addView(header)

        val messageView = TextView(this).apply {
            this.text = message
            setTextColor(Color.rgb(229, 231, 235))
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            setLineSpacing(0f, 1.15f)
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = roundedDrawable(
                color = Color.argb(18, 255, 255, 255),
                radius = dp(18).toFloat(),
                strokeColor = Color.argb(24, 255, 255, 255),
                strokeWidth = dp(1),
            )
        }
        container.addView(
            messageView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(14)
            },
        )
        return container
    }

    private fun roundedDrawable(
        color: Int,
        radius: Float,
        strokeColor: Int? = null,
        strokeWidth: Int = 0,
    ): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            cornerRadius = radius
            if (strokeColor != null && strokeWidth > 0) {
                setStroke(strokeWidth, strokeColor)
            }
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    fun hideTextOverlay() {
        val overlay = textOverlayView ?: return
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        try {
            windowManager.removeView(overlay)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to remove text overlay", e)
        } finally {
            textOverlayView = null
        }
    }

    fun hideDisconnectOverlay() {
        val overlay = disconnectOverlayView ?: return
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        try {
            windowManager.removeView(overlay)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to remove disconnect overlay", e)
        } finally {
            disconnectOverlayView = null
        }
    }

    fun shutdown(): Boolean {
        return try {
            disableSelf()
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to disable accessibility service", e)
            false
        }
    }

    // ============ 手势注入 API ============

    /**
     * 点击
     * @param x X 坐标
     * @param y Y 坐标
     * @param duration 持续时间 (ms)，默认 100ms
     * @return 是否成功
     */
    fun performTap(x: Float, y: Float, duration: Long = 100): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "performTap requires API 24+")
            return false
        }

        val point = normalizePoint(x, y) ?: return false

        val path = Path()
        path.moveTo(point.x, point.y)
        val stroke = GestureDescription.StrokeDescription(path, 0, duration.coerceAtLeast(1L))
        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        Log.d(TAG, "performTap: (${point.x}, ${point.y}) duration=$duration")
        return dispatchGesture(gesture, null, null)
    }

    /**
     * 滑动
     * Android 7 兼容：整段路径一次性提交
     * 
     * @param startX 起始 X
     * @param startY 起始 Y
     * @param endX 结束 X
     * @param endY 结束 Y
     * @param duration 持续时间 (ms)，默认 300ms
     * @return 是否成功
     */
    fun performSwipe(
        startX: Float, startY: Float,
        endX: Float, endY: Float,
        duration: Long = 300
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "performSwipe requires API 24+")
            return false
        }

        val start = normalizePoint(startX, startY) ?: return false
        val end = normalizePoint(endX, endY) ?: return false

        val path = Path()
        path.moveTo(start.x, start.y)
        path.lineTo(end.x, end.y)
        val stroke = GestureDescription.StrokeDescription(path, 0, duration.coerceAtLeast(1L))
        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        Log.d(TAG, "performSwipe: (${start.x}, ${start.y}) -> (${end.x}, ${end.y}) duration=$duration")
        return dispatchGesture(gesture, null, null)
    }

    /**
     * 长按
     * 
     * @param x X 坐标
     * @param y Y 坐标
     * @param duration 持续时间 (ms)，默认 800ms
     * @return 是否成功
     */
    fun performLongPress(x: Float, y: Float, duration: Long = 800): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "performLongPress requires API 24+")
            return false
        }

        val point = normalizePoint(x, y) ?: return false

        val path = Path()
        path.moveTo(point.x, point.y)
        val stroke = GestureDescription.StrokeDescription(path, 0, duration.coerceAtLeast(1L))
        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        Log.d(TAG, "performLongPress: (${point.x}, ${point.y}) duration=$duration")
        return dispatchGesture(gesture, null, null)
    }

    /**
     * 双指缩放
     * Android 7 支持多 Stroke
     * 
     * @param centerX 中心 X
     * @param centerY 中心 Y
     * @param scale 缩放比例 (>1 放大，<1 缩小)
     * @param duration 持续时间 (ms)，默认 200ms
     * @return 是否成功
     */
    fun performPinch(
        centerX: Float, centerY: Float,
        scale: Float,
        duration: Long = 200
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "performPinch requires API 24+")
            return false
        }

        val center = normalizePoint(centerX, centerY) ?: return false
        val bounds = gestureBounds() ?: return false
        val safeScale = scale.coerceIn(0.5f, 3.0f)
        val baseOffset = 100f
        val startLeftOffset = baseOffset.coerceAtMost(center.x)
        val startRightOffset = baseOffset.coerceAtMost(bounds.width - center.x)
        val targetOffset = baseOffset * safeScale
        val endLeftOffset = targetOffset.coerceAtMost(center.x)
        val endRightOffset = targetOffset.coerceAtMost(bounds.width - center.x)

        val path1 = Path()
        path1.moveTo(center.x - startLeftOffset, center.y)
        path1.lineTo(center.x - endLeftOffset, center.y)

        val path2 = Path()
        path2.moveTo(center.x + startRightOffset, center.y)
        path2.lineTo(center.x + endRightOffset, center.y)

        val safeDuration = duration.coerceAtLeast(1L)
        val stroke1 = GestureDescription.StrokeDescription(path1, 0, safeDuration)
        val stroke2 = GestureDescription.StrokeDescription(path2, 0, safeDuration)
        
        val gesture = GestureDescription.Builder()
            .addStroke(stroke1)
            .addStroke(stroke2)
            .build()
        
        Log.d(TAG, "performPinch: center=(${center.x}, ${center.y}) scale=$safeScale duration=$duration")
        return dispatchGesture(gesture, null, null)
    }

    private data class GestureBounds(
        val width: Float,
        val height: Float,
    )

    private fun gestureBounds(): GestureBounds? {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        val metrics = DisplayMetrics()
        if (windowManager != null) {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(metrics)
        } else {
            val fallbackMetrics: DisplayMetrics = resources.displayMetrics ?: return null
            metrics.setTo(fallbackMetrics)
        }
        val width = (metrics.widthPixels - 1).coerceAtLeast(0).toFloat()
        val height = (metrics.heightPixels - 1).coerceAtLeast(0).toFloat()
        if (width <= 0f || height <= 0f) {
            Log.w(TAG, "Gesture bounds unavailable: width=$width height=$height")
            return null
        }
        return GestureBounds(width = width, height = height)
    }

    private fun normalizePoint(x: Float, y: Float): GesturePoint? {
        if (x.isNaN() || y.isNaN() || x.isInfinite() || y.isInfinite()) {
            Log.w(TAG, "Rejecting non-finite gesture point: ($x, $y)")
            return null
        }
        val bounds = gestureBounds() ?: return null
        val safeX = x.coerceIn(0f, bounds.width)
        val safeY = y.coerceIn(0f, bounds.height)
        if (safeX != x || safeY != y) {
            Log.w(TAG, "Clamped gesture point from ($x, $y) to ($safeX, $safeY)")
        }
        return GesturePoint(safeX, safeY)
    }

    /**
     * 执行全局操作
     * 
     * @param action 操作类型 (GLOBAL_ACTION_BACK, GLOBAL_ACTION_HOME, GLOBAL_ACTION_RECENTS)
     * @return 是否成功
     */
    fun performGlobalActionById(action: Int): Boolean {
        Log.d(TAG, "performGlobalAction: $action")
        return performGlobalAction(action)
    }

    /**
     * 获取当前屏幕上的可交互节点
     */
    fun getInteractiveNodes(): List<AccessibilityNodeInfo> {
        val nodes = mutableListOf<AccessibilityNodeInfo>()
        val rootNode = rootInActiveWindow ?: return nodes
        
        fun collectNodes(node: AccessibilityNodeInfo) {
            if (node.isClickable || node.isScrollable || node.isEditable) {
                nodes.add(node)
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { collectNodes(it) }
            }
        }
        
        collectNodes(rootNode)
        return nodes
    }

    fun commitText(text: String): Boolean {
        if (text.isEmpty()) return false
        val node = findFocusedEditableNode() ?: return false
        ensureFocused(node)

        val currentText = node.text?.toString() ?: ""
        val nextText = applyInsertion(node, currentText, text)
        if (setNodeText(node, nextText)) {
            return true
        }

        return pasteText(node, text)
    }

    fun sendKey(keyCode: Int): Boolean {
        val node = findFocusedEditableNode() ?: return false
        ensureFocused(node)
        return when (keyCode) {
            67 -> deleteBackward(node)
            66 -> commitText("\n")
            62 -> commitText(" ")
            61 -> commitText("\t")
            else -> {
                Log.w(TAG, "Unsupported keyCode: $keyCode")
                false
            }
        }
    }

    private fun deleteBackward(node: AccessibilityNodeInfo): Boolean {
        val currentText = node.text?.toString() ?: return false
        if (currentText.isEmpty()) {
            return false
        }

        val selectionStart = node.textSelectionStart.coerceAtLeast(0)
        val selectionEnd = node.textSelectionEnd.coerceAtLeast(0)
        val nextText = when {
            selectionStart in 0..currentText.length &&
                selectionEnd in 0..currentText.length &&
                selectionEnd > selectionStart -> {
                currentText.removeRange(selectionStart, selectionEnd)
            }
            selectionStart in 1..currentText.length -> {
                currentText.removeRange(selectionStart - 1, selectionStart)
            }
            else -> currentText.dropLast(1)
        }
        return setNodeText(node, nextText)
    }

    private fun setNodeText(node: AccessibilityNodeInfo, text: String): Boolean {
        val arguments = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                text,
            )
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
    }

    private fun pasteText(node: AccessibilityNodeInfo, text: String): Boolean {
        val clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            ?: return false
        val previousClip = clipboardManager.primaryClip
        val previousDescription = clipboardManager.primaryClipDescription
        clipboardManager.setPrimaryClip(ClipData.newPlainText("remote_input", text))
        val pasted = node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        if (previousClip != null && previousDescription != null) {
            val restoredClip = ClipData(previousDescription, previousClip.getItemAt(0))
            for (index in 1 until previousClip.itemCount) {
                restoredClip.addItem(previousClip.getItemAt(index))
            }
            clipboardManager.setPrimaryClip(restoredClip)
        } else {
            clipboardManager.setPrimaryClip(ClipData.newPlainText("remote_input", ""))
        }
        return pasted
    }

    private fun ensureFocused(node: AccessibilityNodeInfo) {
        if (!node.isFocused) {
            node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        }
        if (!node.isAccessibilityFocused) {
            node.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS)
        }
    }

    private fun findFocusedEditableNode(): AccessibilityNodeInfo? {
        val rootNode = rootInActiveWindow ?: return null
        val inputFocus = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (inputFocus?.isEditable == true) {
            return inputFocus
        }

        val accessibilityFocus = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
        if (accessibilityFocus?.isEditable == true) {
            return accessibilityFocus
        }

        return null
    }

    private fun applyInsertion(node: AccessibilityNodeInfo, currentText: String, text: String): String {
        val selectionStart = node.textSelectionStart
        val selectionEnd = node.textSelectionEnd
        if (selectionStart < 0 || selectionEnd < 0) {
            return currentText + text
        }

        val safeStart = selectionStart.coerceIn(0, currentText.length)
        val safeEnd = selectionEnd.coerceIn(safeStart, currentText.length)
        return currentText.replaceRange(safeStart, safeEnd, text)
    }
}
