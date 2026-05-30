package lightly.tool

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.HandlerThread
import android.util.DisplayMetrics
import android.util.Log
import android.view.Surface
import android.view.WindowManager
import java.nio.ByteBuffer

class ScreenCapture(
    private val context: Context,
    initialFps: Int = 15,
    initialBitrate: Int = 2_000_000,
    private val onFrameEncoded: (ByteArray, Boolean) -> Unit,
    private val onConfigFrame: (ByteArray, ByteArray) -> Unit
) {
    companion object {
        private const val TAG = "ScreenCapture"
        private const val MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val REPEAT_PREVIOUS_FRAME_AFTER_US = 250_000L
        private const val MAX_CAPTURE_LONG_EDGE = 1920
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var encoder: MediaCodec? = null
    private var inputSurface: Surface? = null
    private var handler: Handler? = null
    private var handlerThread: HandlerThread? = null

    private var screenWidth = 1080
    private var screenHeight = 2340
    private var screenDensityDpi = 440
    private var bitrate = initialBitrate
    private var fps = initialFps

    private var spsData: ByteArray? = null
    private var ppsData: ByteArray? = null
    private var isRunning = false
    private var encodedFrameCount = 0
    private var keyFrameCount = 0
    private var encodedBytesInWindow = 0L
    private var lastEncodedAtMs = 0L
    private var statsWindowStartedAtMs = 0L

    fun start(projection: MediaProjection, width: Int, height: Int, densityDpi: Int) {
        if (isRunning) {
            Log.w(TAG, "Screen capture already running")
            return
        }

        mediaProjection = projection
        val captureSpecs = resolveCaptureSpecs(width, height, densityDpi)

        handlerThread = HandlerThread("ScreenCapture").apply { start() }
        handler = Handler(handlerThread!!.looper)

        var lastError: Exception? = null
        try {
            for ((index, captureSpec) in captureSpecs.withIndex()) {
                screenWidth = captureSpec.width
                screenHeight = captureSpec.height
                screenDensityDpi = captureSpec.densityDpi
                bitrate = captureSpec.bitrate
                fps = captureSpec.fps
                try {
                    resetEncodingStats()
                    setupEncoder(conservative = index > 0)
                    setupVirtualDisplay()
                    isRunning = true
                    Log.i(TAG, "Screen capture started: ${screenWidth}x${screenHeight} @ ${fps}fps bitrate=$bitrate density=${screenDensityDpi} fallbackIndex=$index")
                    return
                } catch (e: Exception) {
                    lastError = e
                    Log.w(TAG, "Screen capture candidate failed: ${captureSpec.width}x${captureSpec.height} @ ${captureSpec.fps}fps bitrate=${captureSpec.bitrate}", e)
                    releaseEncoderAndVirtualDisplayOnly()
                }
            }
            throw lastError ?: IllegalStateException("No supported AVC capture size")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start screen capture", e)
            stop()
            throw e
        }
    }

    private fun setupEncoder(conservative: Boolean) {
        val encoderInstance = MediaCodec.createEncoderByType(MIME_TYPE)
        val profileLevel = selectAvcProfileLevel(encoderInstance.codecInfo)
        ensureSupportedSize(encoderInstance.codecInfo)
        val format = MediaFormat.createVideoFormat(MIME_TYPE, screenWidth, screenHeight).apply {
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(
                MediaFormat.KEY_BITRATE_MODE,
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR,
            )
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
            )
            if (!conservative) {
                setInteger(MediaFormat.KEY_PROFILE, profileLevel.profile)
                setInteger(MediaFormat.KEY_LEVEL, profileLevel.level)
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                setInteger(MediaFormat.KEY_LATENCY, 0)
                setInteger(MediaFormat.KEY_QUALITY, 0)
            }
            setLong(
                MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER,
                REPEAT_PREVIOUS_FRAME_AFTER_US,
            )
            setInteger(MediaFormat.KEY_OPERATING_RATE, fps)
        }

        Log.i(
            TAG,
            "Using AVC profile=${if (conservative) "default" else profileLevel.profile} level=${if (conservative) "default" else profileLevel.level} for ${screenWidth}x${screenHeight} bitrate=$bitrate fps=$fps"
        )

        encoder = encoderInstance.apply {
            setCallback(object : MediaCodec.Callback() {
                override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
                    // Surface 模式不需要处理输入
                }

                override fun onOutputBufferAvailable(
                    codec: MediaCodec, index: Int,
                    info: MediaCodec.BufferInfo
                ) {
                    if (!isRunning) return

                    try {
                        val buffer = codec.getOutputBuffer(index) ?: return
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        val data = ByteArray(info.size)
                        buffer.get(data)

                        val isKeyFrame = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
                        val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0

                        if (isConfig) {
                            if (spsData == null || ppsData == null) {
                                parseConfig(data)
                            }
                        } else {
                            recordEncodedFrame(data.size, isKeyFrame)
                            onFrameEncoded(data, isKeyFrame)
                        }

                        codec.releaseOutputBuffer(index, false)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error processing output buffer", e)
                    }
                }

                override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
                    Log.e(TAG, "Encoder error", e)
                }

                override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
                    Log.d(TAG, "Output format changed: $format")
                    val sps = format.getByteBuffer("csd-0")?.toByteArray()
                    val pps = format.getByteBuffer("csd-1")?.toByteArray()
                    if (sps != null && pps != null) {
                        spsData = sps
                        ppsData = pps
                        onConfigFrame(sps, pps)
                        Log.d(TAG, "Output format config: SPS=${sps.size} PPS=${pps.size}")
                    }
                }
            }, handler)

            configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = createInputSurface()
            start()
        }
    }

    private fun ensureSupportedSize(codecInfo: MediaCodecInfo) {
        val capabilities = try {
            codecInfo.getCapabilitiesForType(MIME_TYPE)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Failed to query AVC size support; trying configure anyway", e)
            return
        }
        val videoCapabilities = capabilities.videoCapabilities ?: return
        if (!videoCapabilities.isSizeSupported(screenWidth, screenHeight)) {
            throw IllegalArgumentException("Unsupported AVC size ${screenWidth}x${screenHeight}")
        }
    }

    private data class AvcProfileLevel(
        val profile: Int,
        val level: Int,
    )

    private fun selectAvcProfileLevel(codecInfo: MediaCodecInfo): AvcProfileLevel {
        val fallback = AvcProfileLevel(
            profile = MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline,
            level = MediaCodecInfo.CodecProfileLevel.AVCLevel31,
        )

        val capabilities = try {
            codecInfo.getCapabilitiesForType(MIME_TYPE)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Failed to query AVC capabilities; using fallback profile/level", e)
            return fallback
        }

        val avcProfiles = capabilities.profileLevels
            .filter {
                it.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileHigh ||
                        it.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileMain ||
                        it.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline
            }
        if (avcProfiles.isEmpty()) {
            return fallback
        }

        val preferredProfiles = listOf(
            MediaCodecInfo.CodecProfileLevel.AVCProfileHigh,
            MediaCodecInfo.CodecProfileLevel.AVCProfileMain,
            MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline,
        )

        for (preferredProfile in preferredProfiles) {
            val candidates = avcProfiles.filter { it.profile == preferredProfile }
            if (candidates.isNotEmpty()) {
                val bestLevel = candidates.maxOf { it.level }
                return AvcProfileLevel(preferredProfile, bestLevel)
            }
        }

        return fallback
    }

    private fun setupVirtualDisplay() {
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "RemoteControl",
            screenWidth,
            screenHeight,
            screenDensityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            inputSurface,
            null,
            handler
        )
    }

    private fun parseConfig(data: ByteArray) {
        // 解析 SPS 和 PPS
        val nalUnits = parseNalUnits(data)
        for (unit in nalUnits) {
            val type = unit[0].toInt() and 0x1F
            when (type) {
                7 -> spsData = unit // SPS
                8 -> ppsData = unit // PPS
            }
        }

        if (spsData != null && ppsData != null) {
            onConfigFrame(spsData!!, ppsData!!)
            Log.d(TAG, "Config frame: SPS=${spsData!!.size} PPS=${ppsData!!.size}")
        }
    }

    private fun parseNalUnits(data: ByteArray): List<ByteArray> {
        val units = mutableListOf<ByteArray>()
        var i = 0

        while (i < data.size - 4) {
            if (data[i].toInt() == 0 && data[i + 1].toInt() == 0) {
                val startCodeLen = when {
                    data[i + 2].toInt() == 0 && data[i + 3].toInt() == 1 -> 4
                    data[i + 2].toInt() == 1 -> 3
                    else -> {
                        i++
                        continue
                    }
                }

                var j = i + startCodeLen
                while (j < data.size - 3) {
                    if (data[j].toInt() == 0 && data[j + 1].toInt() == 0 &&
                        (data[j + 2].toInt() == 1 ||
                                (data[j + 2].toInt() == 0 && j + 3 < data.size && data[j + 3].toInt() == 1))
                    ) {
                        break
                    }
                    j++
                }

                val nalUnit = data.copyOfRange(i + startCodeLen, j)
                units.add(nalUnit)
                i = j
            } else {
                i++
            }
        }

        return units
    }

    fun updateBitrate(newBitrate: Int) {
        bitrate = newBitrate
        val params = android.os.Bundle().apply {
            putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bitrate)
        }
        encoder?.setParameters(params)
        Log.d(TAG, "Bitrate updated to $bitrate")
    }

    fun requestKeyFrame() {
        val params = android.os.Bundle().apply {
            putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
        }
        if (encoder == null) {
            Log.w(TAG, "Key frame requested but encoder is null")
            return
        }
        encoder?.setParameters(params)
        Log.d(TAG, "Key frame requested: frames=$encodedFrameCount keyFrames=$keyFrameCount lastEncodedAgo=${elapsedSinceLastEncoded()}ms")
    }

    fun stop() {
        isRunning = false

        if (encodedFrameCount > 0) {
            Log.i(
                TAG,
                "Screen capture stopping: frames=$encodedFrameCount keyFrames=$keyFrameCount lastEncodedAgo=${elapsedSinceLastEncoded()}ms"
            )
        }

        virtualDisplay?.release()
        virtualDisplay = null

        inputSurface?.release()
        inputSurface = null

        try {
            encoder?.stop()
            encoder?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping encoder", e)
        }
        encoder = null

        mediaProjection?.stop()
        mediaProjection = null

        handlerThread?.quitSafely()
        handlerThread = null
        handler = null

        spsData = null
        ppsData = null

        Log.i(TAG, "Screen capture stopped")
    }

    private fun releaseEncoderAndVirtualDisplayOnly() {
        virtualDisplay?.release()
        virtualDisplay = null

        inputSurface?.release()
        inputSurface = null

        try {
            encoder?.stop()
        } catch (_: Exception) {
        }
        try {
            encoder?.release()
        } catch (_: Exception) {
        }
        encoder = null
        spsData = null
        ppsData = null
    }

    private fun resetEncodingStats() {
        encodedFrameCount = 0
        keyFrameCount = 0
        encodedBytesInWindow = 0L
        val now = System.currentTimeMillis()
        lastEncodedAtMs = 0L
        statsWindowStartedAtMs = now
    }

    private data class CaptureSpec(
        val width: Int,
        val height: Int,
        val densityDpi: Int,
        val fps: Int,
        val bitrate: Int,
    )

    private fun resolveCaptureSpecs(width: Int, height: Int, densityDpi: Int): List<CaptureSpec> {
        val candidates = mutableListOf<CaptureSpec>()
        val longEdge = maxOf(width, height)
        if (longEdge <= MAX_CAPTURE_LONG_EDGE) {
            candidates.add(captureSpec(width, height, densityDpi, fps, bitrate))
        } else {
            val scale = MAX_CAPTURE_LONG_EDGE.toDouble() / longEdge.toDouble()
            val scaledWidth = alignEven(width * scale)
            val scaledHeight = alignEven(height * scale)
            val scaledDensity = (densityDpi * scale).toInt().coerceAtLeast(120)

            Log.i(
                TAG,
                "Scaling capture from ${width}x${height}@${densityDpi}dpi to ${scaledWidth}x${scaledHeight}@${scaledDensity}dpi"
            )

            candidates.add(captureSpec(scaledWidth, scaledHeight, scaledDensity, fps, bitrate))
        }

        val portrait = height >= width
        val fallbackSizes = if (portrait) {
            listOf(720 to 1280, 544 to 960, 360 to 640)
        } else {
            listOf(1280 to 720, 960 to 544, 640 to 360)
        }
        for ((fallbackWidth, fallbackHeight) in fallbackSizes) {
            val scale = fallbackHeight.toDouble() / height.toDouble()
            val fallbackDensity = (densityDpi * scale).toInt().coerceAtLeast(120)
            val fallbackPixels = fallbackWidth * fallbackHeight
            val fallbackBitrate = bitrate.coerceAtMost((fallbackPixels * 2).coerceIn(600_000, 2_500_000))
            candidates.add(captureSpec(fallbackWidth, fallbackHeight, fallbackDensity, fps.coerceAtMost(15), fallbackBitrate))
        }

        return candidates.distinctBy { "${it.width}x${it.height}" }
    }

    private fun captureSpec(width: Int, height: Int, densityDpi: Int, fps: Int, bitrate: Int): CaptureSpec {
        return CaptureSpec(
            width = alignEven(width),
            height = alignEven(height),
            densityDpi = densityDpi,
            fps = fps.coerceIn(5, 30),
            bitrate = bitrate.coerceIn(500_000, 8_000_000),
        )
    }

    private fun alignEven(value: Int): Int = (value and -2).coerceAtLeast(2)

    private fun alignEven(value: Double): Int = alignEven(value.toInt())

    private fun recordEncodedFrame(size: Int, isKeyFrame: Boolean) {
        val now = System.currentTimeMillis()
        if (lastEncodedAtMs != 0L) {
            val gapMs = now - lastEncodedAtMs
            if (gapMs >= 250) {
                Log.w(
                    TAG,
                    "Encoded frame gap detected: gap=${gapMs}ms size=$size key=$isKeyFrame frames=$encodedFrameCount"
                )
            }
        } else {
            Log.i(TAG, "First encoded frame emitted: size=$size key=$isKeyFrame")
        }

        lastEncodedAtMs = now
        encodedFrameCount++
        if (isKeyFrame) {
            keyFrameCount++
        }
        encodedBytesInWindow += size.toLong()

        val windowElapsed = now - statsWindowStartedAtMs
        if (windowElapsed >= 5000) {
            val fps = encodedFrameCount * 1000.0 / windowElapsed
            val avgBytes = if (encodedFrameCount == 0) 0 else encodedBytesInWindow / encodedFrameCount
            Log.d(
                TAG,
                "Encoder stats: frames=$encodedFrameCount keyFrames=$keyFrameCount fps=${"%.1f".format(fps)} avgBytes=$avgBytes bitrate=$bitrate width=$screenWidth height=$screenHeight"
            )
            resetEncodingStats()
            lastEncodedAtMs = now
        }
    }

    private fun elapsedSinceLastEncoded(): Long {
        if (lastEncodedAtMs == 0L) {
            return -1L
        }
        return System.currentTimeMillis() - lastEncodedAtMs
    }

    fun getCaptureInfo(): Map<String, Any> {
        return mapOf(
            "captureWidth" to screenWidth,
            "captureHeight" to screenHeight,
            "density" to screenDensityDpi,
        )
    }

    private fun ByteBuffer.toByteArray(): ByteArray {
        val duplicate = duplicate()
        val bytes = ByteArray(duplicate.remaining())
        duplicate.get(bytes)
        return bytes
    }
}
