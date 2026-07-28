package lightly.tool.plugin.telegram.ipc;

oneway interface ITelegramPluginCallback {
    void onResult(String resultJson);
}
