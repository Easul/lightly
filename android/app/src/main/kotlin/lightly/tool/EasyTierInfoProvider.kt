package lightly.tool

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri

class EasyTierInfoProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? {
        if (uri.authority != expectedAuthority() ||
            uri.pathSegments.firstOrNull() != EasyTierStateStore.PATH_NETWORK_INFO
        ) {
            return null
        }

        val columns = projection?.takeIf { it.isNotEmpty() } ?: DEFAULT_COLUMNS
        val snapshot = EasyTierStateStore.refreshFromJni()
        return MatrixCursor(columns).apply {
            addRow(columns.map { column -> snapshot.valueFor(column) }.toTypedArray())
        }
    }

    override fun getType(uri: Uri): String? {
        if (uri.authority != expectedAuthority() ||
            uri.pathSegments.firstOrNull() != EasyTierStateStore.PATH_NETWORK_INFO
        ) {
            return null
        }
        return "vnd.android.cursor.item/vnd.lightly.easytier.network_info"
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    private fun expectedAuthority(): String =
        EasyTierStateStore.authorityFor(requireNotNull(context).packageName)

    private fun EasyTierStateStore.Snapshot.valueFor(column: String): Any? {
        return when (column) {
            EasyTierStateStore.COLUMN_INSTANCE_NAME -> instanceName
            EasyTierStateStore.COLUMN_RAW_NETWORK_INFO_JSON -> rawNetworkInfoJson
            EasyTierStateStore.COLUMN_VIRTUAL_IPV4 -> virtualIpv4
            EasyTierStateStore.COLUMN_UPDATED_AT -> updatedAtMillis
            EasyTierStateStore.COLUMN_IS_RUNNING -> if (isRunning) 1 else 0
            EasyTierStateStore.COLUMN_ERROR_MESSAGE -> errorMessage
            else -> null
        }
    }

    companion object {
        private val DEFAULT_COLUMNS = arrayOf(
            EasyTierStateStore.COLUMN_INSTANCE_NAME,
            EasyTierStateStore.COLUMN_RAW_NETWORK_INFO_JSON,
            EasyTierStateStore.COLUMN_VIRTUAL_IPV4,
            EasyTierStateStore.COLUMN_UPDATED_AT,
            EasyTierStateStore.COLUMN_IS_RUNNING,
            EasyTierStateStore.COLUMN_ERROR_MESSAGE,
        )
    }
}
