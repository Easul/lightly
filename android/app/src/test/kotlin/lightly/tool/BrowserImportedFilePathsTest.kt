package lightly.tool

import java.io.File
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BrowserImportedFilePathsTest {

    @Test
    fun `sanitizes reserved file name characters`() {
        assertEquals(
            "note_name_.txt",
            BrowserImportedFilePaths.sanitizeFileName(" note/name?.txt ", "fallback.txt"),
        )
    }

    @Test
    fun `uses fallback when display name is blank`() {
        assertEquals(
            "fallback.txt",
            BrowserImportedFilePaths.sanitizeFileName("  ", "fallback.txt"),
        )
    }

    @Test
    fun `adds counter before extension for duplicate file`() {
        val parent = createTempDirectory("imported-files-").toFile()
        try {
            File(parent, "note.txt").createNewFile()
            assertEquals(
                File(parent, "note_1.txt").path,
                BrowserImportedFilePaths.buildUniqueFile(parent, "note.txt").path,
            )
        } finally {
            parent.deleteRecursively()
        }
    }

    @Test
    fun `retains only files below imported roots`() {
        val root = createTempDirectory("imported-root-").toFile()
        try {
            val retained = File(root, "keep.txt")
            val outside = File(root.parentFile, "${root.name}-outside.txt")
            assertTrue(retained.createNewFile())
            assertTrue(outside.createNewFile())
            val paths = BrowserImportedFilePaths.retainedFilePaths(
                listOf(
                    retained.toURI().toString(),
                    outside.toURI().toString(),
                    "https://example.com/file.txt",
                    "file:///%ZZ",
                ),
                listOf(root),
            )
            assertEquals(setOf(retained.canonicalPath), paths)
            outside.delete()
        } finally {
            root.deleteRecursively()
        }
    }
}
