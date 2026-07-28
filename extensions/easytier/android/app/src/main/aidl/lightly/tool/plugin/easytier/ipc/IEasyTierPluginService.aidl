package lightly.tool.plugin.easytier.ipc;

interface IEasyTierPluginService {
    int getApiVersion();
    boolean parseConfig(String config);
    boolean hasVpnPermission();
    boolean startNetwork(String config, String instanceName, boolean useAndroidVpn);
    boolean stopNetwork();
    String getNetworkInfo();
    String getLastError();
}
