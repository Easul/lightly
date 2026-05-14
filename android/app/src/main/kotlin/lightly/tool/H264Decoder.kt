package lightly.tool

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class H264Decoder(private val onFrameDecoded: (Surface) -> Unit) {
    companion object {
        private const val TAG = "H264Decoder"
        private const val MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_AVC
    }

    private var decoder: MediaCodec? = null
    private var surface: Surface? = null
    private var handler: Handler? = null
    private var handlerThread: HandlerThread? = null
    private var isConfigured = false
    private var width = 1080
    private var height = 2340
    private var decodedFrameCount = 0
    private var latestSps: ByteArray? = null
    private var latestPps: ByteArray? = null

    fun configure(surface: Surface, width: Int, height: Int) {
        this.surface = surface
        this.width = width
        this.height = height

        handlerThread = HandlerThread("H264Decoder").apply { start() }
        handler = Handler(handlerThread!!.looper)

        try {
            decoder = MediaCodec.createDecoderByType(MIME_TYPE)
            val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height)
            decoder!!.configure(format, surface, null, 0)
            decoder!!.start()
            isConfigured = true
            Log.i(TAG, "Decoder configured: ${width}x${height}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to configure decoder", e)
            release()
        }
    }

    fun decode(data: ByteArray, isKeyFrame: Boolean, presentationTimeUs: Long) {
        if (!isConfigured || decoder == null) return

        try {
            val normalizedData = normalizeAccessUnit(data, isKeyFrame)
            val inputIndex = decoder!!.dequeueInputBuffer(10000)
            if (inputIndex >= 0) {
                val inputBuffer = decoder!!.getInputBuffer(inputIndex)
                inputBuffer?.clear()
                inputBuffer?.put(normalizedData)
                decoder!!.queueInputBuffer(inputIndex, 0, normalizedData.size, presentationTimeUs, 0)
            } else {
                Log.d(TAG, "No input buffer available for frame len=${normalizedData.size} key=$isKeyFrame")
            }

            val bufferInfo = MediaCodec.BufferInfo()
            var outputIndex = decoder!!.dequeueOutputBuffer(bufferInfo, 10000)
            while (outputIndex >= 0) {
                decoder!!.releaseOutputBuffer(outputIndex, true)
                decodedFrameCount += 1
                if (decodedFrameCount == 1 || decodedFrameCount % 30 == 0) {
                    Log.i(TAG, "Rendered decoded frame #$decodedFrameCount size=${bufferInfo.size}")
                }
                onFrameDecoded(surface!!)
                outputIndex = decoder!!.dequeueOutputBuffer(bufferInfo, 10000)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error decoding frame", e)
        }
    }

    private fun normalizeAccessUnit(data: ByteArray, isKeyFrame: Boolean): ByteArray {
        val normalizedData = normalizeFrameData(data)
        if (!isKeyFrame) return normalizedData

        val hasSps = containsNalType(normalizedData, 7)
        val hasPps = containsNalType(normalizedData, 8)
        if (hasSps && hasPps) return normalizedData

        val sps = latestSps
        val pps = latestPps
        if (sps == null || pps == null) return normalizedData

        val output = ByteArrayOutputStream(sps.size + pps.size + normalizedData.size)
        if (!hasSps) output.write(sps)
        if (!hasPps) output.write(pps)
        output.write(normalizedData)
        Log.d(TAG, "Prepended cached SPS/PPS to key frame len=${normalizedData.size}")
        return output.toByteArray()
    }

    private fun normalizeFrameData(data: ByteArray): ByteArray {
        if (data.isEmpty()) return data
        parseAnnexBNalUnits(data)?.let { return joinNalUnits(it) }
        tryParseAvccNalUnits(data)?.let {
            val joined = joinNalUnits(it)
            Log.d(TAG, "Converted AVCC frame to Annex-B len=${data.size} -> ${joined.size}")
            return joined
        }
        return normalizeSingleNalUnit(data)
    }

    private fun normalizeSingleNalUnit(data: ByteArray): ByteArray {
        if (isAnnexB(data)) return data
        return byteArrayOf(0, 0, 0, 1) + data
    }

    private fun isAnnexB(data: ByteArray): Boolean {
        return (data.size >= 4 &&
                data[0].toInt() == 0 &&
                data[1].toInt() == 0 &&
                ((data[2].toInt() == 1) ||
                        (data[2].toInt() == 0 && data[3].toInt() == 1)))
    }

    private fun tryParseAvccNalUnits(data: ByteArray): List<ByteArray>? {
        val units = mutableListOf<ByteArray>()
        var offset = 0
        while (offset + 4 <= data.size) {
            val nalLength = ByteBuffer.wrap(data, offset, 4).int
            offset += 4
            if (nalLength <= 0 || offset + nalLength > data.size) {
                return null
            }
            units.add(data.copyOfRange(offset, offset + nalLength))
            offset += nalLength
        }
        if (offset != data.size) return null
        return units.takeIf { it.isNotEmpty() }
    }

    private fun parseAnnexBNalUnits(data: ByteArray): List<ByteArray>? {
        val starts = mutableListOf<Int>()
        var index = 0
        while (index <= data.size - 3) {
            val startCodeLength = when {
                index <= data.size - 4 &&
                        data[index].toInt() == 0 &&
                        data[index + 1].toInt() == 0 &&
                        data[index + 2].toInt() == 0 &&
                        data[index + 3].toInt() == 1 -> 4
                data[index].toInt() == 0 &&
                        data[index + 1].toInt() == 0 &&
                        data[index + 2].toInt() == 1 -> 3
                else -> 0
            }
            if (startCodeLength > 0) {
                starts.add(index)
                index += startCodeLength
            } else {
                index += 1
            }
        }
        if (starts.isEmpty()) return null

        val units = mutableListOf<ByteArray>()
        for (i in starts.indices) {
            val start = starts[i]
            val prefixLength = if (
                start <= data.size - 4 &&
                data[start].toInt() == 0 &&
                data[start + 1].toInt() == 0 &&
                data[start + 2].toInt() == 0 &&
                data[start + 3].toInt() == 1
            ) 4 else 3
            val nalStart = start + prefixLength
            val nalEnd = if (i + 1 < starts.size) starts[i + 1] else data.size
            if (nalStart < nalEnd) {
                units.add(data.copyOfRange(nalStart, nalEnd))
            }
        }
        return units.takeIf { it.isNotEmpty() }
    }

    private fun joinNalUnits(nalUnits: List<ByteArray>): ByteArray {
        val output = ByteArrayOutputStream()
        for (nalUnit in nalUnits) {
            output.write(byteArrayOf(0, 0, 0, 1))
            output.write(nalUnit)
        }
        return output.toByteArray()
    }

    private fun containsNalType(data: ByteArray, nalType: Int): Boolean {
        val units = parseAnnexBNalUnits(data) ?: return false
        return units.any { unit -> unit.isNotEmpty() && (unit[0].toInt() and 0x1F) == nalType }
    }

    fun feedConfig(sps: ByteArray, pps: ByteArray) {
        if (!isConfigured || decoder == null) return

        try {
            val normalizedSps = normalizeSingleNalUnit(sps)
            val normalizedPps = normalizeSingleNalUnit(pps)
            latestSps = normalizedSps
            latestPps = normalizedPps
            val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height).apply {
                setByteBuffer("csd-0", ByteBuffer.wrap(normalizedSps))
                setByteBuffer("csd-1", ByteBuffer.wrap(normalizedPps))
            }
            decoder!!.stop()
            decoder!!.configure(format, surface, null, 0)
            decoder!!.start()
            decodedFrameCount = 0
            Log.i(TAG, "Decoder reconfigured with SPS/PPS")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reconfigure decoder", e)
        }
    }

    fun release() {
        isConfigured = false
        decodedFrameCount = 0
        latestSps = null
        latestPps = null
        try {
            decoder?.stop()
            decoder?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing decoder", e)
        }
        decoder = null
        surface = null
        handlerThread?.quitSafely()
        handlerThread = null
        handler = null
        Log.i(TAG, "Decoder released")
    }
}
