package lightly.tool.plugin.liferuntime.ipc;

import android.os.ParcelFileDescriptor;

interface ILifeRuntimePluginService {
    int getApiVersion();
    String start(String serviceId, String optionsJson);
    boolean stop(String serviceId);
    String getStatus();
    String readConfigFiles();
    String writeConfigFiles(String hostConfigJson);
    void stopAll();
    String exportData(in ParcelFileDescriptor destination, String hostConfigJson);
    String importData(in ParcelFileDescriptor source);
}
