package lightly.tool.plugin.liferuntime

import android.content.Context
import android.util.Base64
import org.json.JSONObject
import java.security.SecureRandom
import java.io.File
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.util.concurrent.TimeUnit

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
    private val logRoot = File(runtimeRoot, "logs")

    init {
        listOf(binRoot, workspaceRoot, dataRoot, logRoot).forEach(File::mkdirs)
        copyBundledTools()
    }

    fun hasRunningProcess(): Boolean = synchronized(lock) {
        reapExitedLocked()
        processes.isNotEmpty()
    }

    fun start(serviceId: String, optionsJson: String): String = synchronized(lock) {
        reapExitedLocked()
        if (serviceId != SERVICE_MINDGIT && serviceId != SERVICE_LIFE_RECORD) {
            return error("unknown service: $serviceId")
        }
        processes[serviceId]?.let { return statusFor(it, null) }

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
        val port = options.optInt("port", if (serviceId == SERVICE_MINDGIT) 8787 else 8080)
        if (port !in 1024..65535) return error("port must be between 1024 and 65535")

        val password = if (host == "0.0.0.0") generatePassword() else null
        val command = if (serviceId == SERVICE_MINDGIT) {
            val config = writeMindGitConfig(host, port, root, password)
            listOf(executable.absolutePath, "--config", config.absolutePath)
        } else {
            val data = File(dataRoot, serviceId).apply { mkdirs() }
            listOf(
                executable.absolutePath,
                "serve",
                "--root", root.absolutePath,
                "--data-dir", data.absolutePath,
                "--host", host,
                "--port", port.toString(),
                "--comments", "false",
            )
        }
        val logFile = File(logRoot, "$serviceId.log")
        val process = try {
            ProcessBuilder(command)
                .directory(root)
                .redirectErrorStream(true)
                .redirectOutput(ProcessBuilder.Redirect.appendTo(logFile))
                .apply {
                    environment()["HOME"] = runtimeRoot.absolutePath
                    environment()["TMPDIR"] = File(runtimeRoot, "tmp").apply { mkdirs() }.absolutePath
                    environment()["PATH"] = binRoot.absolutePath
                    environment()["GIT_OPTIONAL_LOCKS"] = "0"
                    if (serviceId == SERVICE_LIFE_RECORD && password != null) {
                        environment()["LIFERECORD_PASSWORD"] = password
                    }
                }
                .start()
        } catch (error: Exception) {
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
            password,
        )
        processes[serviceId] = running
        statusFor(running, null)
    }

    fun stop(serviceId: String): Boolean = synchronized(lock) {
        val running = processes.remove(serviceId) ?: return false
        terminate(running.process)
        true
    }

    fun stopAll() = synchronized(lock) {
        processes.values.toList().forEach { terminate(it.process) }
        processes.clear()
    }

    fun status(): String = synchronized(lock) {
        reapExitedLocked()
        val result = JSONObject()
            .put("runtimeRoot", runtimeRoot.absolutePath)
            .put("installed", JSONObject()
                .put(SERVICE_MINDGIT, executableFor(SERVICE_MINDGIT).canExecute())
                .put(SERVICE_LIFE_RECORD, executableFor(SERVICE_LIFE_RECORD).canExecute()))
        val running = JSONObject()
        processes.values.forEach { running.put(it.id, statusFor(it, null)) }
        result.put("running", running).toString()
    }

    private fun statusFor(process: RunningProcess, message: String?): String {
        return JSONObject()
            .put("service", process.id)
            .put("running", process.process.isAlive)
            .put("host", process.host)
            .put("port", process.port)
            .put("url", "http://${process.host}:${process.port}")
            .put("root", process.root.absolutePath)
            .put("startedAt", process.startedAt)
            .apply { if (process.password != null) put("password", process.password) }
            .apply { if (message != null) put("error", message) }
            .toString()
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

    private fun writeMindGitConfig(host: String, port: Int, root: File, password: String?): File {
        val directory = File(dataRoot, SERVICE_MINDGIT).apply { mkdirs() }
        val config = File(directory, "config.json")
        JSONObject()
            .put("version", 1)
            .put("server", JSONObject().put("bind", host).put("port", port))
            .put(
                "auth",
                JSONObject()
                    .put("enabled", password != null)
                    .put("sessionHours", 12)
                    .apply { if (password != null) put("passwordHash", hashPassword(password)) },
            )
            .put("monitoring", JSONObject().put("enabled", true))
            .put("projects", org.json.JSONArray().put(JSONObject().put("name", "workspace").put("path", root.absolutePath)))
            .put("ssh", JSONObject().put("connections", org.json.JSONArray()))
            .writeTo(config)
        return config
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

    private fun executableFor(serviceId: String): File {
        val nativeExecutable = File(context.applicationInfo.nativeLibraryDir, "lib$serviceId.so")
        return if (nativeExecutable.isFile && nativeExecutable.canExecute()) {
            nativeExecutable
        } else {
            File(binRoot, serviceId)
        }
    }

    private fun JSONObject.writeTo(file: File) {
        file.writeText(toString(2))
    }

    private fun generatePassword(): String {
        val bytes = ByteArray(24)
        SecureRandom().nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.NO_PADDING)
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

    private fun reapExitedLocked() {
        processes.entries.removeIf { !it.value.process.isAlive }
    }

    companion object {
        const val SERVICE_MINDGIT = "mindgit"
        const val SERVICE_LIFE_RECORD = "liferecord"
    }
}
