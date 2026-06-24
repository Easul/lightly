import '../browser_settings.dart';

class BrowserSettingsFormData {
  const BrowserSettingsFormData({
    required this.homepageUrl,
    required this.proxyEnabled,
    required this.proxyHost,
    required this.proxyPortText,
    required this.localProxyPortText,
    required this.proxyUuid,
    required this.proxyServerName,
    required this.proxyTransportPath,
    required this.proxyTransportHost,
    required this.proxyBypassDomains,
    required this.proxyNodes,
    required this.selectedProxyNodeId,
    required this.localHttpRootPath,
    required this.localHttpPortText,
    required this.localHttpUploadKey,
    required this.selectedProtocol,
    required this.proxyPacketEncoding,
    required this.selectedTransportType,
    required this.proxyTlsEnabled,
    required this.proxyTlsInsecure,
    required this.localHttpServerEnabled,
    required this.localHttpBindAllInterfaces,
    required this.nativeVideoPlayerEnabled,
    required this.nativeVideoParserApiBaseUrl,
    required this.openNewWindowInTab,
    required this.appCacheAutoClearEnabled,
    required this.appCacheAutoClearIntervalHours,
  });

  factory BrowserSettingsFormData.fromSettings(BrowserSettings settings) {
    return BrowserSettingsFormData(
      homepageUrl: settings.homepageUrl,
      proxyEnabled: settings.proxyEnabled,
      proxyHost: settings.proxyHost,
      proxyPortText: settings.proxyPort?.toString() ?? '',
      localProxyPortText: settings.localProxyPort?.toString() ?? '',
      proxyUuid: settings.proxyUuid,
      proxyServerName: settings.proxyServerName,
      proxyTransportPath: settings.proxyTransportPath,
      proxyTransportHost: settings.proxyTransportHost,
      proxyBypassDomains: settings.proxyBypassDomains,
      proxyNodes: settings.proxyNodes,
      selectedProxyNodeId: settings.selectedProxyNodeId,
      localHttpRootPath: settings.localHttpRootPath,
      localHttpPortText: settings.localHttpServerPort?.toString() ?? '',
      localHttpUploadKey: settings.localHttpUploadKey,
      selectedProtocol: settings.proxyProtocol,
      proxyPacketEncoding: settings.proxyPacketEncoding,
      selectedTransportType: settings.proxyTransportType,
      proxyTlsEnabled: settings.proxyTlsEnabled,
      proxyTlsInsecure: settings.proxyTlsInsecure,
      localHttpServerEnabled: settings.localHttpServerEnabled,
      localHttpBindAllInterfaces: settings.localHttpBindAllInterfaces,
      nativeVideoPlayerEnabled: settings.nativeVideoPlayerEnabled,
      nativeVideoParserApiBaseUrl: settings.nativeVideoParserApiBaseUrl,
      openNewWindowInTab: settings.openNewWindowInTab,
      appCacheAutoClearEnabled: settings.appCacheAutoClearEnabled,
      appCacheAutoClearIntervalHours: settings.appCacheAutoClearIntervalHours,
    );
  }

  final String homepageUrl;
  final bool proxyEnabled;
  final String proxyHost;
  final String proxyPortText;
  final String localProxyPortText;
  final String proxyUuid;
  final String proxyServerName;
  final String proxyTransportPath;
  final String proxyTransportHost;
  final String proxyBypassDomains;
  final List<BrowserProxyNode> proxyNodes;
  final String? selectedProxyNodeId;
  final String localHttpRootPath;
  final String localHttpPortText;
  final String localHttpUploadKey;
  final String selectedProtocol;
  final String proxyPacketEncoding;
  final String selectedTransportType;
  final bool proxyTlsEnabled;
  final bool proxyTlsInsecure;
  final bool localHttpServerEnabled;
  final bool localHttpBindAllInterfaces;
  final bool nativeVideoPlayerEnabled;
  final String nativeVideoParserApiBaseUrl;
  final bool openNewWindowInTab;
  final bool appCacheAutoClearEnabled;
  final int appCacheAutoClearIntervalHours;

  BrowserSettings toBrowserSettings() {
    return BrowserSettings(
      homepageUrl: homepageUrl,
      proxyEnabled: proxyEnabled,
      proxyHost: proxyHost,
      proxyPort: int.tryParse(proxyPortText),
      proxyScheme: selectedProtocol,
      proxyUuid: proxyUuid,
      proxyTlsEnabled: proxyTlsEnabled,
      proxyTlsInsecure: proxyTlsInsecure,
      proxyServerName: proxyServerName,
      proxyTransportType: selectedTransportType,
      proxyTransportPath: proxyTransportPath,
      proxyTransportHost: proxyTransportHost,
      proxyPacketEncoding: proxyPacketEncoding,
      proxyNodes: proxyNodes,
      selectedProxyNodeId: selectedProxyNodeId,
      proxyBypassDomains: proxyBypassDomains,
      localProxyPort: int.tryParse(localProxyPortText),
      localHttpServerEnabled: localHttpServerEnabled,
      localHttpRootPath: localHttpRootPath,
      localHttpServerPort: int.tryParse(localHttpPortText),
      localHttpBindAllInterfaces: localHttpBindAllInterfaces,
      localHttpUploadKey: localHttpUploadKey,
      nativeVideoPlayerEnabled: nativeVideoPlayerEnabled,
      nativeVideoParserApiBaseUrl: nativeVideoParserApiBaseUrl,
      openNewWindowInTab: openNewWindowInTab,
      appCacheAutoClearEnabled: appCacheAutoClearEnabled,
      appCacheAutoClearIntervalHours: appCacheAutoClearIntervalHours,
    );
  }
}
