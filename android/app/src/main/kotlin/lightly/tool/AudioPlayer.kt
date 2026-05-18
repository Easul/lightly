package lightly.tool

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder

class AudioPlayer(private val context: Context) {
    companion object {
        private const val TAG = "AudioPlayer"
        // 播放增益 — 降为 1.0，因为 AGC 已在采集端完成增益控制
        // 原值 1.2/1.35 与 AGC maxGain=3.5 叠加导致 4.7x 削顶刺啦
        private const val DEFAULT_PLAYBACK_GAIN = 1.0f
        private const val RECEIVER_PLAYBACK_BOOST = 1.0f
    }

    private var audioTrack: AudioTrack? = null
    private var handler: Handler? = null
    private var handlerThread: HandlerThread? = null
    private var isPlaying = false
    private var sampleRate = 16000
    private var channels = 1
    private var useSpeakerphone = false
    private var playbackBoost = 1.0f
    private val audioManager by lazy {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }
    fun initialize(
        sampleRate: Int = 16000,
        channels: Int = 1,
        useSpeakerphone: Boolean = false,
    ) {
        this.sampleRate = sampleRate
        this.channels = channels
        this.useSpeakerphone = useSpeakerphone
        this.playbackBoost = if (useSpeakerphone) RECEIVER_PLAYBACK_BOOST else 1.0f

        val channelConfig = if (channels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
        val minBufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, AudioFormat.ENCODING_PCM_16BIT)
        // 使用 4x minBufferSize 增加缓冲余量，减少播放 underrun 造成的刺啦声
        val bufferSize = if (minBufferSize > 0) {
            minBufferSize * 4
        } else {
            sampleRate / 5 * 4
        }

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

        val audioFormat = AudioFormat.Builder()
            .setSampleRate(sampleRate)
            .setChannelMask(channelConfig)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .build()

        val builder = AudioTrack.Builder()
            .setAudioAttributes(audioAttributes)
            .setAudioFormat(audioFormat)
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        }

        audioTrack = builder.build()

        handlerThread = HandlerThread("AudioPlayer").apply { start() }
        handler = Handler(handlerThread!!.looper)

        Log.i(TAG, "AudioPlayer initialized: $sampleRate Hz, $channels ch")
    }

    fun start() {
        if (isPlaying) return

        try {
            // 不再切换 AudioManager mode 和 speakerphone —
            // 采集端已设置 MODE_IN_COMMUNICATION + speakerphone，
            // 播放端切换到 MODE_NORMAL 会破坏 AEC/NS 通路并产生路由抖动
            audioTrack?.play()
            isPlaying = true
            Log.i(TAG, "AudioPlayer started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start AudioPlayer", e)
        }
    }

    fun play(pcmData: ByteArray) {
        if (!isPlaying || audioTrack == null) return

        handler?.post {
            try {
                val playbackData = if (playbackBoost > 1f) {
                    amplifyPcm16(pcmData, playbackBoost)
                } else {
                    pcmData
                }
                audioTrack?.write(playbackData, 0, playbackData.size)
            } catch (e: Exception) {
                Log.e(TAG, "Error writing audio data", e)
            }
        }
    }

    private fun amplifyPcm16(source: ByteArray, gain: Float): ByteArray {
        val boosted = source.copyOf()
        val buffer = ByteBuffer.wrap(boosted).order(ByteOrder.LITTLE_ENDIAN)
        var index = 0
        while (index + 1 < boosted.size) {
            val sample = buffer.getShort(index).toInt()
            val amplified = (sample * gain).toInt().coerceIn(
                Short.MIN_VALUE.toInt(),
                Short.MAX_VALUE.toInt(),
            )
            buffer.putShort(index, amplified.toShort())
            index += 2
        }
        return boosted
    }

fun stop() {
        if (!isPlaying) return

        try {
            audioTrack?.pause()
            audioTrack?.flush()
            isPlaying = false
            // 不再恢复 AudioManager mode/speakerphone —
            // 采集端负责管理音频路由，播放端不应干扰
            Log.i(TAG, "AudioPlayer stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop AudioPlayer", e)
        }
    }
    }

fun release() {
        try {
            stop()
            audioTrack?.release()
            audioTrack = null
            // 不再恢复 AudioManager mode — 采集端负责音频路由
            Log.i(TAG, "AudioPlayer released")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release AudioPlayer", e)
        }
    }
}
