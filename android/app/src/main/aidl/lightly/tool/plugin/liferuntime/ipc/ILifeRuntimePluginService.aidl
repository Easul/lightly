package lightly.tool.plugin.liferuntime.ipc;

interface ILifeRuntimePluginService {
    int getApiVersion();
    String start(String serviceId, String optionsJson);
    boolean stop(String serviceId);
    String getStatus();
    void stopAll();
}
