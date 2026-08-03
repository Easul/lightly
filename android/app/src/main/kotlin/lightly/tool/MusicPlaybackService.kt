package lightly.tool

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.content.ContextCompat

class MusicPlaybackService : Service() {
    private var mediaPlayer: MediaPlayer? = null
    private lateinit var mediaSession: MediaSession
    private val handler = Handler(Looper.getMainLooper())
    private var notificationEnabled = true
    private var buffering = false
    private var completed = false
    private var trackKey = ""
    private var title = ""
    private var artist = ""
    private var album = ""
    private var artworkUri: String? = null
    private var pendingSeekMs: Int? = null
    private val audioManager by lazy { getSystemService(AUDIO_SERVICE) as AudioManager }
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
        ) {
            pausePlayback()
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        mediaSession = MediaSession(this, "LightlyMusic").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = resumePlayback()
                override fun onPause() = pausePlayback()
                override fun onStop() = stopPlayback()
                override fun onSeekTo(pos: Long) = seekTo(pos.toInt())
            })
            isActive = true
        }
        handler.post(positionReporter)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY -> startTrack(intent)
            ACTION_RESUME -> resumePlayback()
            ACTION_PAUSE -> pausePlayback()
            ACTION_TOGGLE -> if (mediaPlayer?.isPlaying == true) pausePlayback() else resumePlayback()
            ACTION_SEEK -> seekTo(intent.getIntExtra("positionMs", 0))
            ACTION_SET_NOTIFICATION -> {
                notificationEnabled = intent.getBooleanExtra("notificationEnabled", true)
                updateNotification()
                emitState()
                if (mediaPlayer == null) stopSelf()
            }
            ACTION_STOP -> stopPlayback()
        }
        return START_NOT_STICKY
    }

    private fun startTrack(intent: Intent) {
        val uri = intent.getStringExtra("uri") ?: return
        notificationEnabled = intent.getBooleanExtra("notificationEnabled", true)
        trackKey = intent.getStringExtra("trackKey") ?: uri
        title = intent.getStringExtra("title") ?: "未知歌曲"
        artist = intent.getStringExtra("artist") ?: "未知歌手"
        album = intent.getStringExtra("album") ?: "未知专辑"
        artworkUri = intent.getStringExtra("artworkUri")
        buffering = true
        completed = false
        pendingSeekMs = null
        releasePlayer()
        updateMediaSessionMetadata()
        updateNotification()
        emitState()
        try {
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
                setDataSource(applicationContext, Uri.parse(uri))
                setOnPreparedListener {
                    buffering = false
                    requestAudioFocus()
                    pendingSeekMs?.let(it::seekTo)
                    pendingSeekMs = null
                    it.start()
                    updateMediaSessionState()
                    updateNotification()
                    emitState()
                }
                setOnBufferingUpdateListener { _, _ -> emitState() }
                setOnCompletionListener {
                    buffering = false
                    completed = true
                    updateMediaSessionState()
                    updateNotification()
                    emitState()
                }
                setOnErrorListener { _, _, _ ->
                    buffering = false
                    updateMediaSessionState(error = true)
                    releasePlayer()
                    removeForegroundNotification()
                    emitState(error = "播放失败")
                    stopSelf()
                    true
                }
                prepareAsync()
            }
        } catch (_: Exception) {
            buffering = false
            releasePlayer()
            removeForegroundNotification()
            emitState(error = "无法打开音频")
            stopSelf()
        }
    }

    private fun resumePlayback() {
        val player = mediaPlayer ?: return
        if (!player.isPlaying) {
            requestAudioFocus()
            player.start()
        }
        completed = false
        updateMediaSessionState()
        updateNotification()
        emitState()
    }

    private fun pausePlayback() {
        val player = mediaPlayer ?: return
        if (player.isPlaying) player.pause()
        updateMediaSessionState()
        updateNotification()
        emitState()
    }

    private fun seekTo(positionMs: Int) {
        val target = positionMs.coerceAtLeast(0)
        if (buffering) {
            pendingSeekMs = target
        } else {
            mediaPlayer?.runCatching { seekTo(target) }
        }
        completed = false
        updateMediaSessionState()
        emitState()
    }

    private fun stopPlayback() {
        releasePlayer()
        audioManager.abandonAudioFocus(focusListener)
        buffering = false
        completed = false
        trackKey = ""
        removeForegroundNotification()
        emitState()
        stopSelf()
    }

    private fun releasePlayer() {
        mediaPlayer?.let { player ->
            runCatching { player.stop() }
            runCatching { player.reset() }
            runCatching { player.release() }
        }
        mediaPlayer = null
    }

    private fun requestAudioFocus() {
        @Suppress("DEPRECATION")
        audioManager.requestAudioFocus(
            focusListener,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN,
        )
    }

    private fun updateMediaSessionMetadata() {
        mediaSession.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, album)
                .build(),
        )
        updateMediaSessionState()
    }

    private fun updateMediaSessionState(error: Boolean = false) {
        val player = mediaPlayer
        val state = when {
            error -> PlaybackState.STATE_ERROR
            buffering -> PlaybackState.STATE_BUFFERING
            player?.isPlaying == true -> PlaybackState.STATE_PLAYING
            player != null -> PlaybackState.STATE_PAUSED
            else -> PlaybackState.STATE_STOPPED
        }
        mediaSession.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or
                        PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_SEEK_TO or
                        PlaybackState.ACTION_STOP,
                )
                .setState(state, safePosition(player).toLong(), 1f)
                .build(),
        )
    }

    private fun updateNotification() {
        if (!notificationEnabled || trackKey.isEmpty()) {
            removeForegroundNotification()
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFICATION_ID)
            return
        }
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val toggleIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, MusicPlaybackService::class.java).setAction(ACTION_TOGGLE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this,
            2,
            Intent(this, MusicPlaybackService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val playing = mediaPlayer?.isPlaying == true
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title.ifBlank { "若轻音乐" })
            .setContentText(listOf(artist, album).filter { it.isNotBlank() }.joinToString(" · "))
            .setContentIntent(openIntent)
            .setOnlyAlertOnce(true)
            .setOngoing(playing || buffering)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "暂停" else "播放",
                toggleIntent,
            )
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "关闭", stopIntent)
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1),
            )
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "音乐播放",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "显示正在播放的歌曲和播放控制"
                    setShowBadge(false)
                },
            )
        }
    }

    private fun emitState(error: String? = null) {
        val player = mediaPlayer
        val state = mapOf<String, Any?>(
            "trackKey" to trackKey,
            "playing" to (player?.isPlaying == true),
            "buffering" to buffering,
            "completed" to completed,
            "positionMs" to safePosition(player),
            "durationMs" to safeDuration(player),
            "title" to title,
            "artist" to artist,
            "album" to album,
            "artworkUri" to artworkUri,
            "error" to error,
        )
        synchronized(stateLock) {
            lastState = state
        }
        stateListener?.invoke(state)
    }

    private fun safePosition(player: MediaPlayer?): Int {
        return player?.runCatching { currentPosition }?.getOrDefault(0) ?: 0
    }

    private fun safeDuration(player: MediaPlayer?): Int {
        return player?.runCatching { duration }?.getOrDefault(0)?.takeIf { it > 0 } ?: 0
    }

    private fun removeForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private val positionReporter = object : Runnable {
        override fun run() {
            if (mediaPlayer != null) emitState()
            handler.postDelayed(this, 500)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(positionReporter)
        releasePlayer()
        mediaSession.release()
        super.onDestroy()
    }

    companion object {
        const val ACTION_PLAY = "lightly.music.PLAY"
        const val ACTION_RESUME = "lightly.music.RESUME"
        const val ACTION_PAUSE = "lightly.music.PAUSE"
        const val ACTION_TOGGLE = "lightly.music.TOGGLE"
        const val ACTION_STOP = "lightly.music.STOP"
        const val ACTION_SEEK = "lightly.music.SEEK"
        const val ACTION_SET_NOTIFICATION = "lightly.music.SET_NOTIFICATION"
        private const val NOTIFICATION_CHANNEL = "lightly_music_playback"
        private const val NOTIFICATION_ID = 4700
        private val stateLock = Any()
        private var lastState: Map<String, Any?> = mapOf(
            "trackKey" to "",
            "playing" to false,
            "buffering" to false,
            "completed" to false,
            "positionMs" to 0,
            "durationMs" to 0,
        )
        var stateListener: ((Map<String, Any?>) -> Unit)? = null

        fun currentState(): Map<String, Any?> = synchronized(stateLock) { lastState.toMap() }

        fun dispatch(context: Context, intent: Intent) {
            val needsForeground = intent.action == ACTION_PLAY &&
                intent.getBooleanExtra("notificationEnabled", true)
            if (needsForeground) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
