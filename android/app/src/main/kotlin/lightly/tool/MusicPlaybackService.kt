package lightly.tool

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
import android.util.Log
import androidx.core.content.ContextCompat
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors

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
    private var artworkBitmap: Bitmap? = null
    private var artworkRequestId = 0
    private var pendingSeekMs: Int? = null
    private var sourceScheme = ""
    private var prepared = false
    private val artworkExecutor = Executors.newSingleThreadExecutor()
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
                override fun onSkipToPrevious() = requestPlaybackCommand("previous")
                override fun onSkipToNext() = requestPlaybackCommand("next")
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
            ACTION_PREVIOUS -> requestPlaybackCommand("previous")
            ACTION_NEXT -> requestPlaybackCommand("next")
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
        sourceScheme = Uri.parse(uri).scheme?.lowercase().orEmpty()
        notificationEnabled = intent.getBooleanExtra("notificationEnabled", true)
        trackKey = intent.getStringExtra("trackKey") ?: uri
        title = intent.getStringExtra("title") ?: "未知歌曲"
        artist = intent.getStringExtra("artist") ?: "未知歌手"
        album = intent.getStringExtra("album") ?: "未知专辑"
        artworkUri = intent.getStringExtra("artworkUri")
        artworkBitmap = null
        buffering = true
        prepared = false
        completed = false
        pendingSeekMs = null
        releasePlayer()
        updateMediaSessionMetadata()
        updateNotification()
        loadArtworkAsync(artworkUri, trackKey)
        emitState()
        try {
            val player = MediaPlayer()
            mediaPlayer = player
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            player.setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            player.setOnPreparedListener {
                buffering = false
                prepared = true
                requestAudioFocus()
                pendingSeekMs?.let(it::seekTo)
                pendingSeekMs = null
                it.start()
                updateMediaSessionState()
                updateNotification()
                emitState()
            }
            player.setOnBufferingUpdateListener { _, _ -> emitState() }
            player.setOnCompletionListener {
                buffering = false
                completed = true
                updateMediaSessionState()
                updateNotification()
                emitState()
            }
            player.setOnErrorListener { _, what, extra ->
                Log.e(LOG_TAG, "MediaPlayer error what=$what extra=$extra scheme=$sourceScheme")
                buffering = false
                prepared = false
                updateMediaSessionState(error = true)
                releasePlayer()
                removeForegroundNotification()
                emitState(error = mediaErrorMessage(what, extra))
                stopSelf()
                true
            }
            configureDataSource(player, uri)
            player.prepareAsync()
        } catch (error: Exception) {
            Log.e(
                LOG_TAG,
                "Unable to open audio scheme=$sourceScheme type=${error.javaClass.simpleName}",
            )
            buffering = false
            prepared = false
            releasePlayer()
            removeForegroundNotification()
            emitState(error = "无法打开音频（${error.javaClass.simpleName}）")
            stopSelf()
        }
    }

    private fun configureDataSource(player: MediaPlayer, rawUri: String) {
        val uri = Uri.parse(rawUri)
        when (uri.scheme?.lowercase()) {
            "content" -> {
                val descriptor = contentResolver.openAssetFileDescriptor(uri, "r")
                    ?: throw IllegalArgumentException("Audio content is unavailable")
                descriptor.use {
                    if (it.declaredLength >= 0) {
                        player.setDataSource(it.fileDescriptor, it.startOffset, it.declaredLength)
                    } else {
                        player.setDataSource(it.fileDescriptor)
                    }
                }
            }
            "file" -> player.setDataSource(
                uri.path ?: throw IllegalArgumentException("Audio file path is empty"),
            )
            "http", "https" -> player.setDataSource(
                applicationContext,
                uri,
                mapOf(
                    "User-Agent" to BROWSER_USER_AGENT,
                    "Accept" to "audio/*,*/*;q=0.8",
                    "Accept-Encoding" to "identity",
                ),
            )
            else -> player.setDataSource(applicationContext, uri)
        }
    }

    private fun mediaErrorMessage(what: Int, extra: Int): String {
        val reason = when (what) {
            MediaPlayer.MEDIA_ERROR_IO -> "读取失败"
            MediaPlayer.MEDIA_ERROR_MALFORMED -> "文件损坏或编码不支持"
            MediaPlayer.MEDIA_ERROR_UNSUPPORTED -> "格式不支持"
            MediaPlayer.MEDIA_ERROR_TIMED_OUT -> "读取超时"
            MediaPlayer.MEDIA_ERROR_SERVER_DIED -> "媒体服务异常"
            -38 -> "播放器状态异常"
            else -> "未知错误"
        }
        return "播放失败：$reason（$what/$extra）"
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
        prepared = false
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
        prepared = false
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
        val metadata = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadata.METADATA_KEY_ALBUM, album)
        artworkBitmap?.let { bitmap ->
            metadata.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bitmap)
            metadata.putBitmap(MediaMetadata.METADATA_KEY_ART, bitmap)
        }
        mediaSession.setMetadata(metadata.build())
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
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackState.ACTION_SKIP_TO_NEXT or
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
        val previousIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, MusicPlaybackService::class.java).setAction(ACTION_PREVIOUS),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val toggleIntent = PendingIntent.getService(
            this,
            2,
            Intent(this, MusicPlaybackService::class.java).setAction(ACTION_TOGGLE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val nextIntent = PendingIntent.getService(
            this,
            3,
            Intent(this, MusicPlaybackService::class.java).setAction(ACTION_NEXT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this,
            4,
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
            .setLargeIcon(artworkBitmap)
            .addAction(android.R.drawable.ic_media_previous, "上一首", previousIntent)
            .addAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "暂停" else "播放",
                toggleIntent,
            )
            .addAction(android.R.drawable.ic_media_next, "下一首", nextIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "关闭", stopIntent)
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
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

    private fun requestPlaybackCommand(command: String) {
        playbackCommandListener?.invoke(command)
    }

    private fun loadArtworkAsync(rawUri: String?, expectedTrackKey: String) {
        val requestId = ++artworkRequestId
        val value = rawUri?.trim()?.takeIf { it.isNotEmpty() } ?: return
        artworkExecutor.execute {
            val bitmap = runCatching { loadArtwork(value) }.getOrNull() ?: return@execute
            handler.post {
                if (requestId != artworkRequestId || trackKey != expectedTrackKey) {
                    return@post
                }
                artworkBitmap = constrainArtwork(bitmap)
                updateMediaSessionMetadata()
                updateNotification()
            }
        }
    }

    private fun loadArtwork(rawUri: String): Bitmap? {
        val uri = Uri.parse(rawUri)
        return when (uri.scheme?.lowercase()) {
            "content" -> contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream)
            "file" -> uri.path?.let(BitmapFactory::decodeFile)
            "http", "https" -> loadRemoteArtwork(rawUri)
            else -> null
        }
    }

    private fun loadRemoteArtwork(rawUri: String): Bitmap? {
        val directory = File(cacheDir, "music_artwork").apply { mkdirs() }
        val cacheFile = File(directory, "${sha256(rawUri)}.img")
        if (cacheFile.isFile && cacheFile.length() in 1..MAX_ARTWORK_BYTES) {
            BitmapFactory.decodeFile(cacheFile.path)?.let { return it }
        }
        val connection = (URL(rawUri).openConnection() as HttpURLConnection).apply {
            connectTimeout = 8_000
            readTimeout = 12_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", BROWSER_USER_AGENT)
            setRequestProperty("Accept", "image/*")
        }
        return try {
            if (connection.responseCode !in 200..299) return null
            val output = ByteArrayOutputStream()
            connection.inputStream.use { input ->
                val buffer = ByteArray(16 * 1024)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > MAX_ARTWORK_BYTES) return null
                    output.write(buffer, 0, count)
                }
            }
            val bytes = output.toByteArray()
            runCatching { cacheFile.writeBytes(bytes) }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } finally {
            connection.disconnect()
        }
    }

    private fun constrainArtwork(bitmap: Bitmap): Bitmap {
        val largest = maxOf(bitmap.width, bitmap.height)
        if (largest <= MAX_ARTWORK_EDGE) return bitmap
        val scale = MAX_ARTWORK_EDGE.toFloat() / largest
        return Bitmap.createScaledBitmap(
            bitmap,
            (bitmap.width * scale).toInt().coerceAtLeast(1),
            (bitmap.height * scale).toInt().coerceAtLeast(1),
            true,
        )
    }

    private fun sha256(value: String): String {
        return MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun safePosition(player: MediaPlayer?): Int {
        if (!prepared) return 0
        return player?.runCatching { currentPosition }?.getOrDefault(0) ?: 0
    }

    private fun safeDuration(player: MediaPlayer?): Int {
        if (!prepared) return 0
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
        artworkRequestId++
        artworkExecutor.shutdownNow()
        releasePlayer()
        mediaSession.release()
        super.onDestroy()
    }

    companion object {
        const val ACTION_PLAY = "lightly.music.PLAY"
        const val ACTION_RESUME = "lightly.music.RESUME"
        const val ACTION_PAUSE = "lightly.music.PAUSE"
        const val ACTION_TOGGLE = "lightly.music.TOGGLE"
        const val ACTION_PREVIOUS = "lightly.music.PREVIOUS"
        const val ACTION_NEXT = "lightly.music.NEXT"
        const val ACTION_STOP = "lightly.music.STOP"
        const val ACTION_SEEK = "lightly.music.SEEK"
        const val ACTION_SET_NOTIFICATION = "lightly.music.SET_NOTIFICATION"
        private const val NOTIFICATION_CHANNEL = "lightly_music_playback"
        private const val NOTIFICATION_ID = 4700
        private const val LOG_TAG = "LightlyMusic"
        private const val BROWSER_USER_AGENT =
            "Mozilla/5.0 (X11; Linux x86_64; rv:153.0) Gecko/20100101 Firefox/153.0"
        private const val MAX_ARTWORK_BYTES = 5L * 1024L * 1024L
        private const val MAX_ARTWORK_EDGE = 512
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
        var playbackCommandListener: ((String) -> Unit)? = null

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
