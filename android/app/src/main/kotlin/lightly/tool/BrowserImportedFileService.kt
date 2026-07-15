package lightly.tool

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.OpenableColumns
import android.util.Log
import java.io.File
import java.net.URI

class BrowserImportedFileService(
    context: Context,
    private val logTag: String,
) {
    private val appContext = context.applicationContext

    fun importContentUriToPrivateFile(uriString: String): String? {
        val uri = Uri.parse(uriString)
        if (uri.scheme?.lowercase() != "content") {
            return uriString
        }

        val importsDir = resolveImportedDocumentsDir()
        if (!importsDir.exists()) {
            importsDir.mkdirs()
        }

        val displayName = queryContentDisplayName(uri)?.trim().orEmpty()
        val safeName = BrowserImportedFilePaths.sanitizeFileName(
            displayName,
            "imported_${System.currentTimeMillis()}.txt",
        )
        val targetFile = BrowserImportedFilePaths.buildUniqueFile(importsDir, safeName)

        appContext.contentResolver.openInputStream(uri)?.use { input ->
            targetFile.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: return null

        return Uri.fromFile(targetFile).toString()
    }

    fun getContentMimeType(uriString: String): String? {
        return try {
            appContext.contentResolver.getType(Uri.parse(uriString))
        } catch (_: Exception) {
            null
        }
    }

    fun cleanupImportedPrivateFiles(retainedUrls: List<String>): Boolean {
        val importRoots = listOf(
            File(appContext.filesDir, "imported_documents"),
            resolveImportedDocumentsDir(),
        ).map { it.canonicalFile }.distinctBy { it.path }
        val retainedFiles = BrowserImportedFilePaths.retainedFilePaths(retainedUrls, importRoots)

        importRoots.forEach { importsRoot ->
            if (!importsRoot.exists()) {
                return@forEach
            }
            importsRoot.listFiles()?.forEach { child ->
                val canonicalChild = child.canonicalFile
                if (!retainedFiles.contains(canonicalChild.path)) {
                    canonicalChild.delete()
                }
            }
        }

        return true
    }

    private fun resolveImportedDocumentsDir(): File {
        val externalDir = appContext.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS)
        if (externalDir != null) {
            return File(externalDir, "imported_documents")
        }
        return File(appContext.filesDir, "imported_documents")
    }

    private fun queryContentDisplayName(uri: Uri): String? {
        return try {
            appContext.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    return@use null
                }
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index == -1) null else cursor.getString(index)
            }
        } catch (error: Exception) {
            Log.w(logTag, "Failed to query display name for $uri", error)
            null
        }
    }
}

internal object BrowserImportedFilePaths {
    fun sanitizeFileName(rawName: String, fallbackName: String): String {
        val trimmed = rawName.trim()
        val name = if (trimmed.isEmpty()) fallbackName else trimmed
        return name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
    }

    fun buildUniqueFile(parent: File, fileName: String): File {
        val dotIndex = fileName.lastIndexOf('.')
        val baseName = if (dotIndex > 0) fileName.substring(0, dotIndex) else fileName
        val extension = if (dotIndex > 0) fileName.substring(dotIndex) else ""
        var candidate = File(parent, fileName)
        var counter = 1
        while (candidate.exists()) {
            candidate = File(parent, "${baseName}_${counter}${extension}")
            counter += 1
        }
        return candidate
    }

    fun retainedFilePaths(retainedUrls: List<String>, importRoots: List<File>): Set<String> {
        val canonicalRoots = importRoots.map { it.canonicalFile }
        return retainedUrls.mapNotNull { retainedUrl ->
            val path = runCatching {
                val uri = URI(retainedUrl)
                if (!uri.scheme.equals("file", ignoreCase = true)) return@runCatching null
                uri.path ?: return@runCatching null
            }.getOrNull() ?: return@mapNotNull null
            val canonicalPath = runCatching { File(path).canonicalFile.path }.getOrNull()
                ?: return@mapNotNull null
            if (canonicalRoots.any { root ->
                    canonicalPath.startsWith(root.path + File.separator)
                }) {
                canonicalPath
            } else {
                null
            }
        }.toSet()
    }
}
