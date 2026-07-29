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
import kotlin.math.ceil

class H264Decoder(private val onFrameDecoded: (Surface) -> Unit) {
    companion object {
        private const val TAG = "H264Decoder"
        private const val MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val DEQUEUE_TIMEOUT_US = 1_000L
    }

    private var decoder: MediaCodec? = null
    private var surface: Surface? = null
    private var handler: Handler? = null
    private var handlerThread: HandlerThread? = null
    private var isConfigured = false
    private var width = 1080
    private var height = 2340
    private var latestSps: ByteArray? = null
    private var latestPps: ByteArray? = null

    fun configure(surface: Surface, width: Int, height: Int) {
        this.surface = surface
        this.width = width
        this.height = height

        handlerThread = HandlerThread("H264Decoder").apply { start() }
        handler = Handler(handlerThread!!.looper)

        configureDecoder(null)
    }

    private fun configureDecoder(configureFormat: (MediaFormat.() -> Unit)?) {
        val targetSurface = surface ?: return
        try {
            decoder?.release()
            decoder = MediaCodec.createDecoderByType(MIME_TYPE)
            val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height).apply {
                configureFormat?.invoke(this)
            }
            decoder!!.configure(format, targetSurface, null, 0)
            decoder!!.start()
            isConfigured = true
            Log.i(TAG, "Decoder configured: ${width}x${height}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to configure decoder", e)
            try {
                decoder?.release()
            } catch (_: Exception) {
            }
            decoder = null
            isConfigured = false
        }
    }

    fun decode(data: ByteArray, isKeyFrame: Boolean, presentationTimeUs: Long) {
        if (!isConfigured || decoder == null) {
            return
        }

        try {
            val normalizedData = normalizeAccessUnit(data, isKeyFrame)
            val inputIndex = decoder!!.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
            if (inputIndex >= 0) {
                val inputBuffer = decoder!!.getInputBuffer(inputIndex)
                inputBuffer?.clear()
                inputBuffer?.put(normalizedData)
                decoder!!.queueInputBuffer(inputIndex, 0, normalizedData.size, presentationTimeUs, 0)
            }

            val bufferInfo = MediaCodec.BufferInfo()
            var outputIndex = decoder!!.dequeueOutputBuffer(bufferInfo, DEQUEUE_TIMEOUT_US)
            while (outputIndex >= 0) {
                decoder!!.releaseOutputBuffer(outputIndex, true)
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
        return output.toByteArray()
    }

    internal fun normalizeFrameData(data: ByteArray): ByteArray {
        if (data.isEmpty()) return data
        if (isAnnexB(data)) return data
        parseAnnexBNalUnits(data)?.let { return joinNalUnits(it) }
        tryParseAvccNalUnits(data)?.let {
            return joinNalUnits(it)
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
        try {
            val normalizedSps = normalizeSingleNalUnit(sps)
            val normalizedPps = normalizeSingleNalUnit(pps)
            latestSps = normalizedSps
            latestPps = normalizedPps
            updateSizeFromSps(normalizedSps)
            configureDecoder {
                setByteBuffer("csd-0", ByteBuffer.wrap(normalizedSps))
                setByteBuffer("csd-1", ByteBuffer.wrap(normalizedPps))
            }
            Log.i(TAG, "Decoder reconfigured with SPS/PPS")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reconfigure decoder", e)
        }
    }

    private fun updateSizeFromSps(sps: ByteArray) {
        val parsedSize = parseSpsSize(sps)
        if (parsedSize != null) {
            width = parsedSize.first
            height = parsedSize.second
            Log.i(TAG, "Parsed decoder size from SPS: ${width}x${height}")
        }
    }

    private fun parseSpsSize(sps: ByteArray): Pair<Int, Int>? {
        val units = parseAnnexBNalUnits(sps) ?: listOf(sps)
        val unit = units.firstOrNull { it.isNotEmpty() && (it[0].toInt() and 0x1F) == 7 }
            ?: return null
        val rbsp = removeEmulationPreventionBytes(unit.copyOfRange(1, unit.size))
        val reader = BitReader(rbsp)
        return try {
            val profileIdc = reader.readBits(8)
            reader.readBits(8)
            reader.readBits(8)
            reader.readUnsignedExpGolomb()
            if (profileIdc in setOf(100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135)) {
                val chromaFormatIdc = reader.readUnsignedExpGolomb()
                if (chromaFormatIdc == 3) reader.readBit()
                reader.readUnsignedExpGolomb()
                reader.readUnsignedExpGolomb()
                reader.readBit()
                if (reader.readBit() == 1) {
                    val count = if (chromaFormatIdc != 3) 8 else 12
                    repeat(count) {
                        if (reader.readBit() == 1) {
                            skipScalingList(reader, if (it < 6) 16 else 64)
                        }
                    }
                }
            }
            reader.readUnsignedExpGolomb()
            val picOrderCntType = reader.readUnsignedExpGolomb()
            if (picOrderCntType == 0) {
                reader.readUnsignedExpGolomb()
            } else if (picOrderCntType == 1) {
                reader.readBit()
                reader.readSignedExpGolomb()
                reader.readSignedExpGolomb()
                repeat(reader.readUnsignedExpGolomb()) {
                    reader.readSignedExpGolomb()
                }
            }
            reader.readUnsignedExpGolomb()
            reader.readBit()
            val picWidthInMbsMinus1 = reader.readUnsignedExpGolomb()
            val picHeightInMapUnitsMinus1 = reader.readUnsignedExpGolomb()
            val frameMbsOnlyFlag = reader.readBit()
            if (frameMbsOnlyFlag == 0) reader.readBit()
            reader.readBit()
            var cropLeft = 0
            var cropRight = 0
            var cropTop = 0
            var cropBottom = 0
            if (reader.readBit() == 1) {
                cropLeft = reader.readUnsignedExpGolomb()
                cropRight = reader.readUnsignedExpGolomb()
                cropTop = reader.readUnsignedExpGolomb()
                cropBottom = reader.readUnsignedExpGolomb()
            }
            val codedWidth = (picWidthInMbsMinus1 + 1) * 16
            val codedHeight = (picHeightInMapUnitsMinus1 + 1) * 16 * (2 - frameMbsOnlyFlag)
            val cropUnitX = 2
            val cropUnitY = 2 * (2 - frameMbsOnlyFlag)
            val visibleWidth = codedWidth - (cropLeft + cropRight) * cropUnitX
            val visibleHeight = codedHeight - (cropTop + cropBottom) * cropUnitY
            if (visibleWidth > 0 && visibleHeight > 0) visibleWidth to visibleHeight else null
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse SPS size", e)
            null
        }
    }

    private fun removeEmulationPreventionBytes(data: ByteArray): ByteArray {
        val output = ByteArrayOutputStream(data.size)
        var zeroCount = 0
        for (byte in data) {
            if (zeroCount >= 2 && byte.toInt() == 0x03) {
                zeroCount = 0
                continue
            }
            output.write(byte.toInt())
            zeroCount = if (byte.toInt() == 0) zeroCount + 1 else 0
        }
        return output.toByteArray()
    }

    private fun skipScalingList(reader: BitReader, size: Int) {
        var lastScale = 8
        var nextScale = 8
        repeat(size) {
            if (nextScale != 0) {
                val deltaScale = reader.readSignedExpGolomb()
                nextScale = (lastScale + deltaScale + 256) % 256
            }
            lastScale = if (nextScale == 0) lastScale else nextScale
        }
    }

    fun release() {
        isConfigured = false
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

    private class BitReader(private val data: ByteArray) {
        private var bitOffset = 0

        fun readBit(): Int = readBits(1)

        fun readBits(count: Int): Int {
            var value = 0
            repeat(count) {
                val byteIndex = bitOffset / 8
                if (byteIndex >= data.size) {
                    throw IllegalStateException("SPS bitstream exhausted")
                }
                val bitIndex = 7 - (bitOffset % 8)
                value = (value shl 1) or ((data[byteIndex].toInt() shr bitIndex) and 1)
                bitOffset++
            }
            return value
        }

        fun readUnsignedExpGolomb(): Int {
            var leadingZeroBits = 0
            while (readBit() == 0) {
                leadingZeroBits++
            }
            if (leadingZeroBits == 0) return 0
            return ((1 shl leadingZeroBits) - 1) + readBits(leadingZeroBits)
        }

        fun readSignedExpGolomb(): Int {
            val codeNum = readUnsignedExpGolomb()
            val value = ceil(codeNum / 2.0).toInt()
            return if (codeNum % 2 == 0) -value else value
        }
    }
}
