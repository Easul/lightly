package lightly.tool

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri

class OptionalPluginDataProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? {
        if (!isSupportedPath(uri.lastPathSegment)) {
            return null
        }
        val preferences = context?.getSharedPreferences(
            FLUTTER_PREFERENCES_NAME,
            0,
        ) ?: return null
        return MatrixCursor(arrayOf(COLUMN_JSON)).apply {
            addRow(arrayOf(preferences.getString(TELEGRAM_CONFIG_KEY, null)))
        }
    }

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int {
        if (!isSupportedPath(uri.lastPathSegment)) {
            return 0
        }
        val json = values?.getAsString(COLUMN_JSON) ?: return 0
        val preferences = context?.getSharedPreferences(
            FLUTTER_PREFERENCES_NAME,
            0,
        ) ?: return 0
        return if (preferences.edit().putString(TELEGRAM_CONFIG_KEY, json).commit()) 1 else 0
    }

    override fun getType(uri: Uri): String = MIME_TYPE

    override fun insert(uri: Uri, values: ContentValues?): Uri? {
        return if (update(uri, values, null, null) == 1) uri else null
    }

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int {
        return 0
    }

    companion object {
        // This key remains owned by Lightly so normal backup/import keeps working.
        const val TELEGRAM_CONFIG_PATH = "telegram_config"
        const val COLUMN_JSON = "json"
        internal fun isSupportedPath(path: String?): Boolean = path == TELEGRAM_CONFIG_PATH

        private const val FLUTTER_PREFERENCES_NAME = "FlutterSharedPreferences"
        private const val TELEGRAM_CONFIG_KEY = "flutter.telegram_checkin_config"
        private const val MIME_TYPE =
            "vnd.android.cursor.item/vnd.lightly.optional-plugin.telegram-config"
    }
}
