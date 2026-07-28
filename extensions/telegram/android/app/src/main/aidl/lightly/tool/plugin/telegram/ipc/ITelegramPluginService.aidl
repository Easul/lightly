package lightly.tool.plugin.telegram.ipc;

import lightly.tool.plugin.telegram.ipc.ITelegramPluginCallback;

interface ITelegramPluginService {
    int getApiVersion();
    int createClient();
    oneway void send(int clientId, String requestJson);
    String execute(String requestJson);
    void registerCallback(ITelegramPluginCallback callback);
    void unregisterCallback(ITelegramPluginCallback callback);
}
