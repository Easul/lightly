package lightly.tool.plugin.webrtc.ipc;

import lightly.tool.plugin.webrtc.ipc.IWebRtcVoicePluginCallback;

interface IWebRtcVoicePluginService {
    int getApiVersion();
    void registerCallback(IWebRtcVoicePluginCallback callback);
    void unregisterCallback(IWebRtcVoicePluginCallback callback);
    void request(String requestJson);
}
