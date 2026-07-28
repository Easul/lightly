package lightly.tool.plugin.telegram

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.io.File
import kotlin.io.path.createTempDirectory

class TelegramRequestSanitizerTest {
    @Test
    fun `rewrites TDLib storage into plugin private directories`() {
        val root = createTempDirectory("telegram-plugin-").toFile()
        val database = File(root, "database")
        val files = File(root, "files")
        val sanitizer = TelegramRequestSanitizer(database, files)

        val rewritten = JSONObject(
            sanitizer.rewrite(
                """{"@type":"setTdlibParameters","database_directory":"/host/db","files_directory":"/host/files"}""",
            ),
        )

        assertEquals(database.absolutePath, rewritten.getString("database_directory"))
        assertEquals(files.absolutePath, rewritten.getString("files_directory"))
        assertFalse(rewritten.toString().contains("/host/"))
        root.deleteRecursively()
    }

    @Test
    fun `leaves unrelated TDLib requests byte-for-byte unchanged`() {
        val sanitizer = TelegramRequestSanitizer(File("unused-db"), File("unused-files"))
        val request = """{"@type":"getAuthorizationState","@extra":"1"}"""

        assertEquals(request, sanitizer.rewrite(request))
    }
}
