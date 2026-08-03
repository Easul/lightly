package lightly.tool

import android.Manifest
import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MusicPlayerChannelHandler(
    private val activity: Activity,
) {
    private var channel: MethodChannel? = null
    private var pendingAudioIntent: Map<String, Any?>? = null
    private var pendingAudioPermission: MethodChannel.Result? = null
    private var pendingNotificationPermission: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleteUri: Uri? = null

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME).also { registered ->
            registered.setMethodCallHandler(::handle)
        }
        MusicPlaybackService.stateListener = { state ->
            activity.runOnUiThread {
                channel?.invokeMethod("onPlaybackState", state)
            }
        }
        MusicPlaybackService.playbackCommandListener = { command ->
            activity.runOnUiThread {
                channel?.invokeMethod("onPlaybackCommand", mapOf("command" to command))
            }
        }
    }

    fun publishExternalAudioIntent(uri: String, mimeType: String?, intentFlags: Int) {
        persistUriPermissionIfOffered(Uri.parse(uri), intentFlags)
        val metadata = resolveAudioMetadata(Uri.parse(uri)).toMutableMap().apply {
            put("uri", uri)
            put("mimeType", mimeType)
        }
        pendingAudioIntent = metadata
        activity.runOnUiThread {
            channel?.invokeMethod("onExternalAudioIntent", metadata)
        }
    }

    private fun persistUriPermissionIfOffered(uri: Uri, intentFlags: Int) {
        if (uri.scheme != "content" ||
            intentFlags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION == 0
        ) {
            return
        }
        val takeFlags = intentFlags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        runCatching {
            activity.contentResolver.takePersistableUriPermission(uri, takeFlags)
        }
    }

    fun handleRequestPermissionsResult(requestCode: Int): Boolean {
        when (requestCode) {
            AUDIO_PERMISSION_REQUEST -> {
                val result = pendingAudioPermission ?: return true
                pendingAudioPermission = null
                result.success(hasAudioPermission())
                return true
            }
            NOTIFICATION_PERMISSION_REQUEST -> {
                val result = pendingNotificationPermission ?: return true
                pendingNotificationPermission = null
                result.success(hasNotificationPermission())
                return true
            }
        }
        return false
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != DELETE_AUDIO_REQUEST) return false
        val result = pendingDeleteResult ?: return true
        val uri = pendingDeleteUri
        pendingDeleteResult = null
        pendingDeleteUri = null
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(false)
            return true
        }
        try {
            val deleted = activity.contentResolver.delete(uri, null, null) > 0
            result.success(deleted || !contentUriExists(uri))
        } catch (error: Exception) {
            result.error("DELETE_FAILED", error.message ?: "Unable to delete audio", null)
        }
        return true
    }

    fun shutdown() {
        pendingDeleteResult?.error("ACTIVITY_CLOSED", "Activity closed during delete", null)
        pendingDeleteResult = null
        pendingDeleteUri = null
        MusicPlaybackService.stateListener = null
        MusicPlaybackService.playbackCommandListener = null
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scanLocalMusic" -> scanLocalMusic(result)
            "deleteLocalAudio" -> deleteLocalAudio(call, result)
            "hasAudioPermission" -> result.success(hasAudioPermission())
            "requestAudioPermission" -> requestAudioPermission(result)
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "play" -> dispatchPlayback(call, MusicPlaybackService.ACTION_PLAY, result)
            "resume" -> dispatch(MusicPlaybackService.ACTION_RESUME, result)
            "pause" -> dispatch(MusicPlaybackService.ACTION_PAUSE, result)
            "stop" -> dispatch(MusicPlaybackService.ACTION_STOP, result)
            "seekTo" -> dispatchPlayback(call, MusicPlaybackService.ACTION_SEEK, result)
            "setNotificationEnabled" -> dispatchPlayback(
                call,
                MusicPlaybackService.ACTION_SET_NOTIFICATION,
                result,
            )
            "getState" -> result.success(MusicPlaybackService.currentState())
            "getPendingAudioIntent" -> {
                val pending = pendingAudioIntent
                pendingAudioIntent = null
                result.success(pending)
            }
            else -> result.notImplemented()
        }
    }

    private fun deleteLocalAudio(call: MethodCall, result: MethodChannel.Result) {
        val rawUri = call.argument<String>("uri")?.trim().orEmpty()
        if (rawUri.isEmpty()) {
            result.error("INVALID_URI", "Audio URI is empty", null)
            return
        }
        val uri = Uri.parse(rawUri)
        when (uri.scheme?.lowercase()) {
            "file" -> {
                val path = uri.path
                if (path.isNullOrEmpty()) {
                    result.error("INVALID_URI", "File path is empty", null)
                    return
                }
                val file = File(path)
                result.success(!file.exists() || file.delete())
            }
            "content" -> deleteContentAudio(uri, result)
            else -> result.error("UNSUPPORTED_URI", "Only local audio can be deleted", null)
        }
    }

    private fun deleteContentAudio(uri: Uri, result: MethodChannel.Result) {
        if (pendingDeleteResult != null) {
            result.error("IN_PROGRESS", "Another audio deletion is in progress", null)
            return
        }
        try {
            val deleted = activity.contentResolver.delete(uri, null, null) > 0
            result.success(deleted || !contentUriExists(uri))
        } catch (recoverable: RecoverableSecurityException) {
            requestDeleteConfirmation(uri, recoverable.userAction.actionIntent.intentSender, result)
        } catch (security: SecurityException) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val sender = runCatching {
                    MediaStore.createDeleteRequest(
                        activity.contentResolver,
                        listOf(uri),
                    ).intentSender
                }.getOrNull()
                if (sender != null) {
                    requestDeleteConfirmation(uri, sender, result)
                } else {
                    result.error("DELETE_PERMISSION_DENIED", security.message, null)
                }
            } else {
                result.error("DELETE_PERMISSION_DENIED", security.message, null)
            }
        } catch (error: Exception) {
            result.error("DELETE_FAILED", error.message, null)
        }
    }

    private fun requestDeleteConfirmation(
        uri: Uri,
        sender: android.content.IntentSender,
        result: MethodChannel.Result,
    ) {
        pendingDeleteResult = result
        pendingDeleteUri = uri
        try {
            activity.startIntentSenderForResult(
                sender,
                DELETE_AUDIO_REQUEST,
                null,
                0,
                0,
                0,
            )
        } catch (error: Exception) {
            pendingDeleteResult = null
            pendingDeleteUri = null
            result.error("DELETE_CONFIRMATION_FAILED", error.message, null)
        }
    }

    private fun contentUriExists(uri: Uri): Boolean {
        return runCatching {
            activity.contentResolver.query(uri, arrayOf(MediaStore.Audio.Media._ID), null, null, null)
                ?.use { it.moveToFirst() } == true
        }.getOrDefault(true)
    }

    private fun dispatch(action: String, result: MethodChannel.Result) {
        MusicPlaybackService.dispatch(activity, Intent(activity, MusicPlaybackService::class.java).apply {
            this.action = action
        })
        result.success(null)
    }

    private fun dispatchPlayback(
        call: MethodCall,
        action: String,
        result: MethodChannel.Result,
    ) {
        val intent = Intent(activity, MusicPlaybackService::class.java).apply {
            this.action = action
            call.argument<String>("uri")?.let { putExtra("uri", it) }
            call.argument<String>("trackKey")?.let { putExtra("trackKey", it) }
            call.argument<String>("title")?.let { putExtra("title", it) }
            call.argument<String>("artist")?.let { putExtra("artist", it) }
            call.argument<String>("album")?.let { putExtra("album", it) }
            call.argument<String>("artworkUri")?.let { putExtra("artworkUri", it) }
            call.argument<Int>("positionMs")?.let { putExtra("positionMs", it) }
            call.argument<Boolean>("notificationEnabled")?.let {
                putExtra("notificationEnabled", it)
            }
            call.argument<Boolean>("enabled")?.let {
                putExtra("notificationEnabled", it)
            }
        }
        MusicPlaybackService.dispatch(activity, intent)
        result.success(null)
    }

    private fun scanLocalMusic(result: MethodChannel.Result) {
        if (!hasAudioPermission()) {
            result.error("PERMISSION_DENIED", "Audio permission is required", null)
            return
        }
        try {
            val projection = mutableListOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM,
                MediaStore.Audio.Media.ALBUM_ID,
                MediaStore.Audio.Media.DURATION,
                MediaStore.Audio.Media.DISPLAY_NAME,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                projection.add(MediaStore.MediaColumns.RELATIVE_PATH)
                projection.add(MediaStore.MediaColumns.VOLUME_NAME)
            } else {
                projection.add(MediaStore.Audio.Media.DATA)
            }
            val songs = mutableListOf<Map<String, Any?>>()
            activity.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection.toTypedArray(),
                "${MediaStore.Audio.Media.IS_MUSIC} != 0",
                null,
                "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val albumIdColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
                val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val dataColumn = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
                val relativePathColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                } else {
                    -1
                }
                val volumeNameColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    cursor.getColumnIndex(MediaStore.MediaColumns.VOLUME_NAME)
                } else {
                    -1
                }
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idColumn)
                    val albumId = cursor.getLong(albumIdColumn)
                    val displayName = cursor.getString(nameColumn)
                    val displayPath = buildDisplayPath(
                        dataPath = dataColumn.takeIf { it >= 0 }?.let(cursor::getString),
                        relativePath = relativePathColumn.takeIf { it >= 0 }
                            ?.let(cursor::getString),
                        volumeName = volumeNameColumn.takeIf { it >= 0 }
                            ?.let(cursor::getString),
                        displayName = displayName,
                    )
                    songs.add(
                        mapOf(
                            "id" to id,
                            "uri" to ContentUris.withAppendedId(
                                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                                id,
                            ).toString(),
                            "title" to repairMediaText(cursor.getString(titleColumn)),
                            "artist" to cleanUnknown(cursor.getString(artistColumn), "未知歌手"),
                            "album" to cleanUnknown(cursor.getString(albumColumn), "未知专辑"),
                            "artworkUri" to "content://media/external/audio/albumart/$albumId",
                            "durationMs" to cursor.getLong(durationColumn),
                            "displayName" to displayName,
                            "path" to displayPath,
                        ),
                    )
                }
            }
            result.success(songs)
        } catch (error: Exception) {
            result.error("SCAN_FAILED", error.message, null)
        }
    }

    private fun resolveAudioMetadata(uri: Uri): Map<String, Any?> {
        val fallbackName = uri.lastPathSegment?.substringAfterLast('/') ?: "本地歌曲"
        val values = mutableMapOf<String, Any?>(
            "title" to File(fallbackName).nameWithoutExtension,
            "artist" to "未知歌手",
            "album" to "未知专辑",
            "displayName" to fallbackName,
            "path" to if (uri.scheme == "file") uri.path else null,
            "durationMs" to 0L,
        )
        runCatching {
            activity.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return@use
                fun read(column: String): String? {
                    val index = cursor.getColumnIndex(column)
                    return if (index >= 0) cursor.getString(index) else null
                }
                fun readLong(column: String): Long? {
                    val index = cursor.getColumnIndex(column)
                    return if (index >= 0) cursor.getLong(index) else null
                }
                values["title"] = repairMediaText(read(MediaStore.Audio.Media.TITLE))
                    ?: repairMediaText(read(MediaStore.Audio.Media.DISPLAY_NAME)?.substringBeforeLast('.'))
                    ?: values["title"]
                values["artist"] = cleanUnknown(read(MediaStore.Audio.Media.ARTIST), "未知歌手")
                values["album"] = cleanUnknown(read(MediaStore.Audio.Media.ALBUM), "未知专辑")
                values["displayName"] = read(MediaStore.Audio.Media.DISPLAY_NAME) ?: fallbackName
                values["durationMs"] = readLong(MediaStore.Audio.Media.DURATION) ?: 0L
                val albumId = readLong(MediaStore.Audio.Media.ALBUM_ID)
                if (albumId != null) {
                    values["artworkUri"] = "content://media/external/audio/albumart/$albumId"
                }
                values["path"] = buildDisplayPath(
                    dataPath = read(MediaStore.Audio.Media.DATA),
                    relativePath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        read(MediaStore.MediaColumns.RELATIVE_PATH)
                    } else {
                        null
                    },
                    volumeName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        read(MediaStore.MediaColumns.VOLUME_NAME)
                    } else {
                        null
                    },
                    displayName = values["displayName"]?.toString(),
                )
            }
        }
        return values
    }

    private fun buildDisplayPath(
        dataPath: String?,
        relativePath: String?,
        volumeName: String?,
        displayName: String?,
    ): String? {
        dataPath?.trim()?.takeIf { it.startsWith("/storage/") }?.let { return it }
        val relative = relativePath?.trim('/')?.takeIf { it.isNotEmpty() } ?: return null
        val name = displayName?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val root = when {
            volumeName.isNullOrBlank() || volumeName == MediaStore.VOLUME_EXTERNAL_PRIMARY -> {
                "/storage/emulated/0"
            }
            volumeName == MediaStore.VOLUME_EXTERNAL -> return null
            else -> "/storage/$volumeName"
        }
        return "$root/$relative/$name".replace(Regex("/{2,}"), "/")
    }

    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(true)
            return
        }
        if (pendingAudioPermission != null) {
            result.error("IN_PROGRESS", "Audio permission request already in progress", null)
            return
        }
        pendingAudioPermission = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(audioPermission()),
            AUDIO_PERMISSION_REQUEST,
        )
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (hasNotificationPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (pendingNotificationPermission != null) {
            result.error("IN_PROGRESS", "Notification permission request already in progress", null)
            return
        }
        pendingNotificationPermission = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun hasAudioPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return ContextCompat.checkSelfPermission(activity, audioPermission()) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun audioPermission(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    private fun cleanUnknown(value: String?, fallback: String): String {
        return repairMediaText(value)?.takeUnless { it == "<unknown>" } ?: fallback
    }

    // A few legacy ID3 tags are UTF-8 bytes decoded as Latin-1 by MediaStore.
    // Repair only when the candidate produces CJK text, avoiding changes to real
    // names that legitimately contain accented Latin characters.
    private fun repairMediaText(value: String?): String? {
        val text = value?.trim()?.takeUnless { it.isEmpty() || it == "null" } ?: return null
        if (text.any(::isCjk) || text.count { it in '\u00C0'..'\u00FF' } < 2) {
            return text
        }
        val repaired = runCatching {
            String(text.toByteArray(Charsets.ISO_8859_1), Charsets.UTF_8)
        }.getOrNull()
        return if (repaired != null && repaired.any(::isCjk)) repaired else text
    }

    private fun isCjk(value: Char): Boolean {
        return value in '\u3400'..'\u4DBF' || value in '\u4E00'..'\u9FFF'
    }

    companion object {
        const val CHANNEL_NAME = "lightly_music_player"
        private const val AUDIO_PERMISSION_REQUEST = 4701
        private const val NOTIFICATION_PERMISSION_REQUEST = 4702
        private const val DELETE_AUDIO_REQUEST = 4703
    }
}
