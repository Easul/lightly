package lightly.tool

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class TranslationHistoryStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    @Synchronized
    fun list(): List<Map<String, Any>> {
        val array = readArray()
        return (0 until array.length()).mapNotNull { index ->
            array.optJSONObject(index)?.toMap()
        }
    }

    @Synchronized
    fun save(entry: Map<String, Any?>) {
        val array = readArray()
        val updated = JSONArray().apply {
            put(JSONObject(entry))
            for (index in 0 until minOf(array.length(), MAX_HISTORY - 1)) {
                put(array.getJSONObject(index))
            }
        }
        store(updated)
    }

    @Synchronized
    fun update(entry: Map<String, Any?>) {
        val id = entry["id"]?.toString() ?: return
        val array = readArray()
        val updated = JSONArray()
        for (index in 0 until array.length()) {
            val item = array.getJSONObject(index)
            updated.put(if (item.optString("id") == id) JSONObject(entry) else item)
        }
        store(updated)
    }

    @Synchronized
    fun delete(id: String) {
        val array = readArray()
        val updated = JSONArray()
        for (index in 0 until array.length()) {
            val item = array.getJSONObject(index)
            if (item.optString("id") != id) updated.put(item)
        }
        store(updated)
    }

    @Synchronized
    fun clear() {
        preferences.edit().remove(HISTORY_KEY).apply()
    }

    private fun readArray(): JSONArray {
        val raw = preferences.getString(HISTORY_KEY, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun store(array: JSONArray) {
        preferences.edit().putString(HISTORY_KEY, array.toString()).apply()
    }

    private fun JSONObject.toMap(): Map<String, Any> = mapOf(
        "id" to optString("id"),
        "source" to optString("source"),
        "translation" to optString("translation"),
        "targetLanguage" to optString("targetLanguage", "自动"),
        "createdAt" to optLong("createdAt"),
    )

    companion object {
        private const val PREFERENCES_NAME = "translation_overlay"
        private const val HISTORY_KEY = "history"
        private const val MAX_HISTORY = 200
    }
}
