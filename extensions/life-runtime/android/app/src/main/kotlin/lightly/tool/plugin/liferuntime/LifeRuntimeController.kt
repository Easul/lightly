package lightly.tool.plugin.liferuntime

import android.content.Context
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.security.SecureRandom
import java.io.File
import android.os.ParcelFileDescriptor
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.util.concurrent.TimeUnit
import java.net.NetworkInterface

internal class LifeRuntimeController(private val context: Context) {
    private data class RunningProcess(
        val id: String,
        val process: Process,
        val host: String,
        val port: Int,
        val root: File,
        val startedAt: Long,
        val password: String?,
    )

    private val lock = Any()
    private val processes = mutableMapOf<String, RunningProcess>()
    private val runtimeRoot = File(context.filesDir, "runtime")
    private val binRoot = File(runtimeRoot, "bin")
    private val workspaceRoot = File(runtimeRoot, "workspaces")
    private val dataRoot = File(runtimeRoot, "data")
    private val logRoot = File(workspaceRoot, "life-runtime/logs")
    private val gitRoot = File(runtimeRoot, "git")

    init {
        listOf(binRoot, workspaceRoot, dataRoot, logRoot).forEach(File::mkdirs)
        copyBundledTools()
        prepareGitLinks()
    }

    fun hasRunningProcess(): Boolean = synchronized(lock) {
        processes.values.any { it.process.isAlive }
    }

    fun start(serviceId: String, optionsJson: String): String = synchronized(lock) {
        if (serviceId != SERVICE_MINDGIT && serviceId != SERVICE_LIFE_RECORD) {
            return error("unknown service: $serviceId")
        }
        processes[serviceId]?.let {
            if (it.process.isAlive) return statusFor(it, null)
            processes.remove(serviceId)
        }

        val options = runCatching { JSONObject(optionsJson.ifBlank { "{}" }) }
            .getOrElse { return error("invalid options: ${it.message}") }
        val executable = executableFor(serviceId)
        if (!executable.isFile || !executable.canExecute()) {
            return error(
                "$serviceId is not executable: path=${executable.absolutePath}, " +
                    "exists=${executable.isFile}, canExecute=${executable.canExecute()}, " +
                    "nativeLibraryDir=${context.applicationInfo.nativeLibraryDir}",
            )
        }

        val root = resolveWorkspace(options.optString("root", "default"))
            ?: return error("workspace must be a child of ${workspaceRoot.path}")
        root.mkdirs()
        val host = options.optString("host", "127.0.0.1")
        if (host != "127.0.0.1" && host != "0.0.0.0") {
            return error("host must be 127.0.0.1 or 0.0.0.0")
        }
        if (host == "0.0.0.0" && !options.optBoolean("allowLan", false)) {
            return error("LAN binding requires explicit allowLan=true")
        }
        val port = options.optInt("port", if (serviceId == SERVICE_MINDGIT) 8787 else 8347)
        if (port !in 1024..65535) return error("port must be between 1024 and 65535")

        val configuredPassword = options.optString("password", "").trim().takeIf { it.isNotEmpty() }
        if (serviceId == SERVICE_MINDGIT && (configuredPassword?.length ?: 0) < 8) {
            return error("MindGit password must contain at least 8 characters")
        }
        val passwordEnv = options.optString("passwordEnv", "").trim()
        val runtimePasswordEnv = if (configuredPassword == null) {
            DISABLED_PASSWORD_ENV
        } else {
            passwordEnv.ifEmpty { PRIVATE_PASSWORD_ENV }
        }
        val command = if (serviceId == SERVICE_MINDGIT) {
            val config = writeMindGitConfig(host, port, root, configuredPassword)
            val directories = resolveMindGitDirectories(options, root)
                ?: return error("MindGit directories must be relative children of ${workspaceRoot.path}")
            buildList {
                addAll(listOf(executable.absolutePath, "--config", config.absolutePath))
                directories.forEach { directory ->
                    val relative = directory.relativeTo(config.parentFile ?: workspaceRoot).path
                    addAll(listOf("-d", if (relative.isEmpty() || relative == ".") "./" else relative))
                }
            }
        } else {
            val data = resolveDataDirectory(optionText(options, "dataDir", "life-record/data"))
                ?: return error("dataDir must be a relative child of ${workspaceRoot.path}")
            data.mkdirs()
            val config = writeLifeRecordConfig(options, root, data, host, port, runtimePasswordEnv)
            buildList {
                addAll(listOf(
                executable.absolutePath,
                "serve",
                "--config", config.absolutePath,
                "--host", host,
                "--port", port.toString(),
                "--root", root.absolutePath,
                "--data-dir", data.absolutePath,
                ))
                val baseUrl = options.optString("baseUrl", "").trim()
                if (baseUrl.isNotEmpty()) addAll(listOf("--base-url", baseUrl))
                addAll(listOf("--password-env", runtimePasswordEnv))
            }
        }
        val logFile = File(logRoot, "$serviceId.log")
        val processDirectory = if (serviceId == SERVICE_MINDGIT) workspaceRoot else root
        val process = try {
            Log.i(TAG, "starting $serviceId: ${command.first()} host=$host port=$port")
            ProcessBuilder(command)
                .directory(processDirectory)
                .redirectErrorStream(true)
                .apply {
                    environment()["HOME"] = runtimeRoot.absolutePath
                    environment()["TMPDIR"] = File(runtimeRoot, "tmp").apply { mkdirs() }.absolutePath
                    environment()["PATH"] = "${binRoot.absolutePath}:${context.applicationInfo.nativeLibraryDir}"
                    environment()["LD_LIBRARY_PATH"] = "${context.applicationInfo.nativeLibraryDir}:${gitRoot.resolve("lib").absolutePath}"
                    environment()["GIT_EXEC_PATH"] = binRoot.absolutePath
                    environment()["GIT_TEMPLATE_DIR"] = File(gitRoot, "share/git-core/templates").absolutePath
                    environment()["GIT_OPTIONAL_LOCKS"] = "0"
                    if (serviceId == SERVICE_LIFE_RECORD) {
                        if (configuredPassword != null) environment()[runtimePasswordEnv] = configuredPassword
                    }
                }
                .start()
        } catch (error: Exception) {
            Log.e(TAG, "failed to start $serviceId: ${executable.absolutePath}", error)
            return error(
                "failed to start $serviceId: ${error.message}; " +
                    "executable=${executable.absolutePath}",
            )
        }
        val running = RunningProcess(
            serviceId,
            process,
            host,
            port,
            root,
            System.currentTimeMillis(),
            configuredPassword,
        )
        processes[serviceId] = running
        Thread {
            runCatching {
                logFile.parentFile?.mkdirs()
                logFile.bufferedWriter(Charsets.UTF_8, 8192).use { writer ->
                    process.inputStream.bufferedReader().useLines { lines ->
                        lines.forEach { line ->
                            writer.appendLine(line)
                            writer.flush()
                            Log.i("$TAG/$serviceId", line)
                        }
                    }
                }
            }
        }.apply { name = "life-runtime-log-$serviceId" }.start()
        Thread {
            val exitCode = runCatching { process.waitFor() }.getOrElse { return@Thread }
            Log.e(TAG, "$serviceId exited with code $exitCode")
            runCatching {
                logFile.appendText("process exited with code $exitCode\n")
            }
        }.apply { name = "life-runtime-$serviceId" }.start()
        statusFor(running, null)
    }

    fun stop(serviceId: String): Boolean = synchronized(lock) {
        val running = processes.remove(serviceId) ?: run {
            Log.i(TAG, "stop ignored for $serviceId: process is not tracked")
            return false
        }
        Log.i(TAG, "stopping $serviceId")
        terminate(running.process)
        Log.i(TAG, "stopped $serviceId")
        true
    }

    fun stopAll() = synchronized(lock) {
        processes.values.toList().forEach { terminate(it.process) }
        processes.clear()
    }

    fun exportData(destination: ParcelFileDescriptor, hostConfigJson: String): String {
        synchronized(lock) {
            if (processes.isNotEmpty()) return error("stop services before exporting data")
            return runCatching {
                ZipOutputStream(BufferedOutputStream(FileOutputStream(destination.fileDescriptor))).use { zip ->
                    writeZipText(zip, "manifest.json", "{\"version\":1,\"type\":\"life-runtime\"}")
                    writeZipText(zip, "host-config.json", hostConfigJson)
                    addDirectoryToZip(zip, workspaceRoot, "workspaces")
                    addDirectoryToZip(zip, dataRoot, "data")
                }
                JSONObject().put("ok", true).toString()
            }.getOrElse { error("export failed: ${it.message}") }
        }
    }

    fun importData(source: ParcelFileDescriptor): String {
        synchronized(lock) {
            stopAll()
            return runCatching {
                var hostConfig = "{}"
                var entries = 0
                var bytes = 0L
                ZipInputStream(BufferedInputStream(FileInputStream(source.fileDescriptor))).use { zip ->
                    while (true) {
                        val entry = zip.nextEntry ?: break
                        entries++
                        if (entries > MAX_ARCHIVE_ENTRIES) throw IllegalArgumentException("archive has too many entries")
                        val relative = safeArchivePath(entry.name)
                            ?: throw IllegalArgumentException("invalid archive path")
                        if (relative == "manifest.json") {
                            val body = zip.readLimited(MAX_CONFIG_BYTES).toString(StandardCharsets.UTF_8)
                            if (!body.contains("\"type\":\"life-runtime\"")) throw IllegalArgumentException("invalid life-runtime archive")
                        } else if (relative == "host-config.json") {
                            hostConfig = zip.readLimited(MAX_CONFIG_BYTES).toString(StandardCharsets.UTF_8)
                            JSONObject(hostConfig)
                        } else if (!entry.isDirectory && (relative.startsWith("workspaces/") || relative.startsWith("data/"))) {
                            val target = File(runtimeRoot, relative)
                            val body = zip.readLimited(MAX_FILE_BYTES) {
                                bytes += it
                                if (bytes > MAX_ARCHIVE_BYTES) {
                                    throw IllegalArgumentException("archive is too large")
                                }
                            }
                            val base = runtimeRoot.canonicalFile.toPath()
                            if (!target.canonicalFile.toPath().startsWith(base)) {
                                throw IllegalArgumentException("archive path escapes runtime root")
                            }
                            target.parentFile?.mkdirs()
                            FileOutputStream(target).use { it.write(body) }
                        }
                        zip.closeEntry()
                    }
                }
                JSONObject().put("ok", true).put("configJson", hostConfig).toString()
            }.getOrElse { error("import failed: ${it.message}") }
        }
    }

    fun status(): String = synchronized(lock) {
        val result = JSONObject()
            .put("runtimeRoot", runtimeRoot.absolutePath)
            .put("installed", JSONObject()
                .put(SERVICE_MINDGIT, executableFor(SERVICE_MINDGIT).canExecute())
                .put(SERVICE_LIFE_RECORD, executableFor(SERVICE_LIFE_RECORD).canExecute()))
        val running = JSONObject()
        processes.values.forEach { running.put(it.id, JSONObject(statusFor(it, null))) }
        result.put("running", running).toString()
    }

    private fun statusFor(process: RunningProcess, message: String?): String {
        val displayHost = if (process.host == "0.0.0.0") lanAddress() else process.host
        return JSONObject()
            .put("service", process.id)
            .put("running", process.process.isAlive)
            .put("host", process.host)
            .put("port", process.port)
            .put("url", "http://$displayHost:${process.port}")
            .put("root", process.root.absolutePath)
            .put("startedAt", process.startedAt)
            .apply { if (process.password != null) put("password", process.password) }
            .apply {
                if (!process.process.isAlive) {
                    put("exitCode", runCatching { process.process.exitValue() }.getOrDefault(-1))
                    val log = File(logRoot, "${process.id}.log")
                    if (log.isFile) put("lastLog", log.readLines().takeLast(8).joinToString("\n"))
                }
            }
            .apply { if (message != null) put("error", message) }
            .toString()
    }

    private fun lanAddress(): String {
        return runCatching {
            NetworkInterface.getNetworkInterfaces().toList()
                .asSequence()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList().asSequence() }
                .filter { !it.isLoopbackAddress && it.hostAddress?.contains(':') == false }
                .mapNotNull { it.hostAddress }
                .firstOrNull()
        }.getOrNull() ?: "0.0.0.0"
    }

    private fun error(message: String): String = JSONObject().put("error", message).toString()

    private fun resolveWorkspace(value: String): File? {
        val candidate = if (value.isBlank() || value == "default") {
            File(workspaceRoot, "default")
        } else {
            File(workspaceRoot, value)
        }
        val rootPath = workspaceRoot.canonicalFile.toPath()
        val candidatePath = runCatching { candidate.canonicalFile.toPath() }.getOrNull() ?: return null
        return if (candidatePath.startsWith(rootPath)) candidate else null
    }

    private fun resolveDataDirectory(value: String): File? {
        if (File(value).isAbsolute) return null
        val candidate = File(workspaceRoot, value)
        val base = workspaceRoot.canonicalFile.toPath()
        val path = runCatching { candidate.canonicalFile.toPath() }.getOrNull() ?: return null
        return if (path.startsWith(base)) candidate else null
    }

    private fun resolveMindGitDirectories(options: JSONObject, fallback: File): List<File>? {
        val values = options.optJSONArray("directories")
        val requested = if (values == null || values.length() == 0) {
            listOf(".")
        } else {
            (0 until values.length()).map { values.optString(it).trim() }.filter { it.isNotEmpty() }
        }
        if (requested.isEmpty()) return listOf(fallback)
        val base = workspaceRoot.canonicalFile.toPath()
        return requested.map { relative ->
            if (File(relative).isAbsolute) return null
            val candidate = File(workspaceRoot, relative)
            val path = runCatching { candidate.canonicalFile.toPath() }.getOrNull() ?: return null
            if (!path.startsWith(base)) return null
            candidate.apply { mkdirs() }
        }
    }

    private fun writeMindGitConfig(host: String, port: Int, root: File, password: String?): File {
        val config = File(workspaceRoot, ".mindgit.json")
        JSONObject()
            .put("version", 1)
            .put("server", JSONObject().put("bind", host).put("port", port))
            .put(
                "auth",
                JSONObject()
                    .put("enabled", !password.isNullOrEmpty())
                    .put("sessionHours", 12)
                    .apply { if (!password.isNullOrEmpty()) put("passwordHash", hashPassword(password)) },
            )
            .put("monitoring", JSONObject().put("enabled", true))
            .put("projects", org.json.JSONArray().put(JSONObject().put("name", "workspace").put("path", root.absolutePath)))
            .put("ssh", JSONObject().put("connections", org.json.JSONArray()))
            .writeTo(config)
        return config
    }

    private fun writeLifeRecordConfig(
        options: JSONObject,
        root: File,
        data: File,
        host: String,
        port: Int,
        passwordEnv: String,
    ): File {
        val config = File(workspaceRoot, "life-record").apply { mkdirs() }.resolve("config.yaml")
        val ai = options.optJSONObject("ai") ?: JSONObject()
        val excludes = options.optJSONArray("excludeDirs") ?: org.json.JSONArray()
        val lines = mutableListOf(
            "title: ${yaml(optionText(options, "title", "人生记录"))}",
            "root: ${yaml(root.absolutePath)}",
            "host: ${yaml(host)}",
            "port: $port",
            "data_dir: ${yaml(data.absolutePath)}",
            "mode: ${yaml(optionText(options, "mode", "preview"))}",
            "base_url: ${yaml(options.optString("baseUrl", "").trim())}",
            "comments: ${options.optBoolean("comments", true)}",
            "refresh: ${yaml(optionText(options, "refresh", "2s"))}",
            "password_env: ${yaml(passwordEnv)}",
            "exclude_dirs:",
        )
        for (index in 0 until excludes.length()) lines += "  - ${yaml(excludes.optString(index))}"
        lines += listOf(
            "ai:",
            "  enabled: ${ai.optBoolean("enabled", false)}",
            "  api_key: ${yaml(ai.optString("apiKey", ""))}",
            "  base_url: ${yaml(ai.optString("baseUrl", "https://api.openai.com"))}",
            "  api_type: ${yaml(ai.optString("apiType", "chat_completions"))}",
            "  model: ${yaml(ai.optString("model", "gpt-4o-mini"))}",
            "  thinking: ${ai.optBoolean("thinking", true)}",
            "  tools: ${ai.optBoolean("tools", true)}",
            "  system_prompt: ${yaml(ai.optString("systemPrompt", ""))}",
        )
        config.writeText(lines.joinToString("\n") + "\n")
        return config
    }

    private fun yaml(value: String): String = "'" + value.replace("'", "''") + "'"

    private fun optionText(options: JSONObject, key: String, fallback: String): String {
        val value = options.optString(key, "").trim()
        return if (value.isEmpty()) fallback else value
    }

    private fun copyBundledTools() {
        val names = runCatching { context.assets.list("bin")?.toList().orEmpty() }
            .getOrDefault(emptyList())
        names.forEach { name ->
            val target = File(binRoot, name)
            if (target.isFile && target.canExecute()) return@forEach
            runCatching {
                context.assets.open("bin/$name").use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
                target.setReadable(true, false)
                target.setExecutable(true, false)
            }
        }
    }

    private fun prepareGitLinks() {
        val native = File(context.applicationInfo.nativeLibraryDir)
        val git = File(native, "libgit.so")
        if (!git.isFile) return
        gitRoot.mkdirs()
        val gitLibDir = gitRoot.resolve("lib")
        gitLibDir.deleteRecursively()
        copyAssetTree("git/lib", gitLibDir)
        val links = mapOf(
            "git" to git,
            "git-receive-pack" to git,
            "git-upload-pack" to git,
            "git-upload-archive" to git,
            "git-remote-http" to File(native, "libgit_remote_http.so"),
            "git-remote-https" to File(native, "libgit_remote_http.so"),
            "git-remote-ftp" to File(native, "libgit_remote_http.so"),
            "git-remote-ftps" to File(native, "libgit_remote_http.so"),
            "ssh" to File(native, "libssh.so"),
            "rg" to File(native, "librg.so"),
            "unzip" to File(native, "libunzip.so"),
            "zip" to File(native, "libzip.so"),
            "ls" to File("/system/bin/toybox"),
            "clear" to File("/system/bin/toybox"),
            "mv" to File("/system/bin/toybox"),
            "cat" to File("/system/bin/toybox"),
            "rm" to File("/system/bin/toybox"),
        )
        links.forEach { (name, target) ->
            if (!target.isFile) return@forEach
            val link = File(binRoot, name)
            if (java.nio.file.Files.isSymbolicLink(link.toPath())) link.delete()
            if (link.exists() || link.isFile) return@forEach
            runCatching { java.nio.file.Files.createSymbolicLink(link.toPath(), target.toPath()) }
        }
        val assetTemplates = File(gitRoot, "share/git-core/templates")
        assetTemplates.deleteRecursively()
        assetTemplates.parentFile?.mkdirs()
        copyAssetTree("git/share/git-core/templates", assetTemplates)
    }

    private fun copyAssetTree(assetPath: String, destination: File) {
        val children = runCatching { context.assets.list(assetPath)?.toList().orEmpty() }.getOrDefault(emptyList())
        if (children.isEmpty()) {
            destination.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input -> destination.outputStream().use { input.copyTo(it) } }
            return
        }
        destination.mkdirs()
        children.forEach { child -> copyAssetTree("$assetPath/$child", File(destination, child)) }
    }

    private fun executableFor(serviceId: String): File {
        val nativeExecutable = File(context.applicationInfo.nativeLibraryDir, "lib$serviceId.so")
        return if (nativeExecutable.isFile && nativeExecutable.canExecute()) {
            nativeExecutable
        } else {
            File(binRoot, serviceId)
        }
    }

    private fun addDirectoryToZip(zip: ZipOutputStream, directory: File, prefix: String) {
        if (!directory.exists()) return
        directory.walkTopDown().filter { it.isFile }.forEach { file ->
            val relative = file.relativeTo(directory).path.replace(File.separatorChar, '/')
            zip.putNextEntry(ZipEntry("$prefix/$relative"))
            file.inputStream().use { it.copyTo(zip) }
            zip.closeEntry()
        }
    }

    private fun writeZipText(zip: ZipOutputStream, name: String, text: String) {
        zip.putNextEntry(ZipEntry(name))
        zip.write(text.toByteArray(StandardCharsets.UTF_8))
        zip.closeEntry()
    }

    private fun safeArchivePath(value: String): String? {
        val normalized = value.replace('\\', '/')
        if (normalized.startsWith('/') || normalized.contains('\u0000')) return null
        val parts = normalized.split('/')
        if (parts.any { it == ".." }) return null
        return parts.filter { it.isNotEmpty() && it != "." }.joinToString("/").takeIf { it.isNotEmpty() }
    }

    private fun java.io.InputStream.readLimited(limit: Long, onBytes: (Long) -> Unit = {}): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        var total = 0L
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            total += count
            if (total > limit) throw IllegalArgumentException("archive entry is too large")
            output.write(buffer, 0, count)
            onBytes(count.toLong())
        }
        return output.toByteArray()
    }

    private fun JSONObject.writeTo(file: File) {
        file.writeText(toString(2))
    }

    private fun hashPassword(password: String): String {
        val salt = ByteArray(16)
        SecureRandom().nextBytes(salt)
        val derived = pbkdf2(password.toByteArray(Charsets.UTF_8), salt, 210000, 32)
        return "pbkdf2-sha256\$210000\$${Base64.encodeToString(salt, Base64.NO_WRAP or Base64.NO_PADDING)}\$${Base64.encodeToString(derived, Base64.NO_WRAP or Base64.NO_PADDING)}"
    }

    private fun pbkdf2(password: ByteArray, salt: ByteArray, iterations: Int, length: Int): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(password, "HmacSHA256"))
        val output = ByteArray(length)
        var offset = 0
        var block = 1
        while (offset < length) {
            mac.reset()
            mac.update(salt)
            mac.update(byteArrayOf(0, 0, 0, (block and 0xff).toByte()))
            var value = mac.doFinal()
            val result = value.copyOf()
            repeat(iterations - 1) {
                mac.reset()
                value = mac.doFinal(value)
                for (index in result.indices) result[index] = (result[index].toInt() xor value[index].toInt()).toByte()
            }
            val count = minOf(result.size, length - offset)
            result.copyInto(output, offset, 0, count)
            offset += count
            block++
        }
        return output
    }

    private fun terminate(process: Process) {
        process.destroy()
        if (!process.waitFor(2, TimeUnit.SECONDS)) process.destroyForcibly()
    }

    companion object {
        private const val TAG = "LifeRuntimeController"
        private const val MAX_ARCHIVE_ENTRIES = 10000
        private const val MAX_ARCHIVE_BYTES = 512L * 1024L * 1024L
        private const val MAX_CONFIG_BYTES = 256 * 1024L
        private const val MAX_FILE_BYTES = 128L * 1024L * 1024L
        private const val PRIVATE_PASSWORD_ENV = "LIGHTLY_LIFERECORD_PASSWORD"
        private const val DISABLED_PASSWORD_ENV = "LIGHTLY_LIFERECORD_PASSWORD_DISABLED"
        const val SERVICE_MINDGIT = "mindgit"
        const val SERVICE_LIFE_RECORD = "liferecord"
    }
}
