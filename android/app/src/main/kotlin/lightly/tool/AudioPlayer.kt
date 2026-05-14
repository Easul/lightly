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
        private const val DEFAULT_PLAYBACK_GAIN = 1.2f
        private const val RECEIVER_PLAYBACK_BOOST = 1.35f
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
        val bufferSize = if (minBufferSize > 0) {
            minBufferSize
        } else {
            sampleRate / 5
        }

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
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
            if (audioManager.mode == AudioManager.MODE_IN_COMMUNICATION) {
                audioManager.mode = AudioManager.MODE_NORMAL
            }
            if (audioManager.isSpeakerphoneOn) {
                audioManager.isSpeakerphoneOn = false
            }
            audioTrack?.setVolume(DEFAULT_PLAYBACK_GAIN)
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
            audioTrack?.stop()
            isPlaying = false
            Log.i(TAG, "AudioPlayer stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop AudioPlayer", e)
        }
    }

    fun release() {
        stop()
        audioTrack?.release()
        audioTrack = null
        handlerThread?.quitSafely()
        handlerThread = null
        handler = null
        Log.i(TAG, "AudioPlayer released")
    }
}
