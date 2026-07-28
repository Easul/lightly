package lightly.tool.plugin.telegram

import org.json.JSONObject
import java.io.File

internal class TelegramRequestSanitizer(
    private val databaseDirectory: File,
    private val filesDirectory: File,
) {
    fun rewrite(requestJson: String): String {
        val request = JSONObject(requestJson)
        if (request.optString(TYPE_KEY) != SET_PARAMETERS_TYPE) {
            return requestJson
        }
        databaseDirectory.mkdirs()
        filesDirectory.mkdirs()
        request.put(DATABASE_DIRECTORY_KEY, databaseDirectory.absolutePath)
        request.put(FILES_DIRECTORY_KEY, filesDirectory.absolutePath)
        return request.toString()
    }

    companion object {
        private const val TYPE_KEY = "@type"
        private const val SET_PARAMETERS_TYPE = "setTdlibParameters"
        private const val DATABASE_DIRECTORY_KEY = "database_directory"
        private const val FILES_DIRECTORY_KEY = "files_directory"
    }
}
