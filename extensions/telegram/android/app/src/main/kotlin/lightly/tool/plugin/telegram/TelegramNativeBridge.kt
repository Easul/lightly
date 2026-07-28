package lightly.tool.plugin.telegram

internal object TelegramNativeBridge {
    init {
        System.loadLibrary("tdjson")
        System.loadLibrary("telegram_bridge")
    }

    external fun createClient(): Int
    external fun send(clientId: Int, requestJson: String)
    external fun receive(timeoutSeconds: Double): String?
    external fun execute(requestJson: String): String?
}
