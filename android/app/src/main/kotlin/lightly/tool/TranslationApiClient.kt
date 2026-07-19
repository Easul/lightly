package lightly.tool

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

data class TranslationApiConfig(
    val baseUrl: String,
    val apiKey: String,
    val model: String,
    val endpoint: String,
)

class TranslationApiClient {
    fun translate(config: TranslationApiConfig, text: String): String {
        val endpointPath = when (config.endpoint) {
            "openAiCompletions" -> "completions"
            "anthropicMessages" -> "messages"
            else -> "responses"
        }
        val connection = URL(buildUrl(config.baseUrl, endpointPath)).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 20_000
            connection.readTimeout = 60_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            if (config.apiKey.isNotBlank()) {
                connection.setRequestProperty("Authorization", "Bearer ${config.apiKey}")
                if (config.endpoint == "anthropicMessages") {
                    connection.setRequestProperty("x-api-key", config.apiKey)
                    connection.setRequestProperty("anthropic-version", "2023-06-01")
                }
            }
            connection.outputStream.bufferedWriter(Charsets.UTF_8).use { writer ->
                writer.write(buildBody(config, text).toString())
            }
            val responseText = readResponse(connection)
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("请求失败（${connection.responseCode}）：${extractError(responseText)}")
            }
            return extractText(config.endpoint, JSONObject(responseText)).trim().ifEmpty {
                throw IllegalStateException("接口未返回文本内容")
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun buildBody(config: TranslationApiConfig, text: String): JSONObject {
        val system = "You are a translation tool. Return only the translated text, without explanation, quotation marks, or notes."
        val user = "Detect whether the input is primarily Chinese or English. Translate Chinese to English and English to Simplified Chinese.\n\n$text"
        return when (config.endpoint) {
            "openAiCompletions" -> JSONObject().apply {
                put("model", config.model)
                put("prompt", "System: $system\nUser: $user\nAssistant:")
                put("stream", false)
                put("max_tokens", 2048)
            }
            "anthropicMessages" -> JSONObject().apply {
                put("model", config.model)
                put("system", system)
                put("messages", JSONArray().put(JSONObject().apply {
                    put("role", "user")
                    put("content", user)
                }))
                put("stream", false)
                put("max_tokens", 2048)
            }
            else -> JSONObject().apply {
                put("model", config.model)
                put("input", JSONArray().apply {
                    put(JSONObject().apply {
                        put("role", "system")
                        put("content", system)
                    })
                    put(JSONObject().apply {
                        put("role", "user")
                        put("content", user)
                    })
                })
                put("stream", false)
            }
        }
    }

    private fun extractText(endpoint: String, root: JSONObject): String = when (endpoint) {
        "openAiCompletions" -> {
            val choice = root.optJSONArray("choices")?.optJSONObject(0)
            choice?.optString("text").orEmpty().ifEmpty {
                choice?.optJSONObject("message")?.optString("content").orEmpty()
            }
        }
        "anthropicMessages" -> {
            val content = root.optJSONArray("content") ?: JSONArray()
            buildString {
                for (index in 0 until content.length()) {
                    append(content.optJSONObject(index)?.optString("text").orEmpty())
                }
            }
        }
        else -> root.optString("output_text").ifEmpty {
            val output = root.optJSONArray("output") ?: JSONArray()
            buildString {
                for (index in 0 until output.length()) {
                    val content = output.optJSONObject(index)?.optJSONArray("content") ?: continue
                    for (partIndex in 0 until content.length()) {
                        append(content.optJSONObject(partIndex)?.optString("text").orEmpty())
                    }
                }
            }
        }
    }

    private fun extractError(body: String): String = try {
        val root = JSONObject(body)
        val error = root.opt("error")
        when (error) {
            is JSONObject -> error.optString("message", error.toString())
            null -> body
            else -> error.toString()
        }
    } catch (_: Exception) {
        body
    }

    private fun readResponse(connection: HttpURLConnection): String {
        val stream = if (connection.responseCode in 200..299) {
            connection.inputStream
        } else {
            connection.errorStream ?: connection.inputStream
        }
        return stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    private fun buildUrl(baseUrl: String, resource: String): String {
        val normalized = baseUrl.trim().trimEnd('/')
        require(normalized.isNotEmpty()) { "请先填写 Base URL" }
        return when {
            normalized.endsWith("/v1/$resource") -> normalized
            normalized.endsWith("/v1") -> "$normalized/$resource"
            else -> "$normalized/v1/$resource"
        }
    }
}
