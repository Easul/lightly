import 'package:flutter/material.dart';

import '../browser_settings.dart';
import '../models/browser_settings_form_data.dart';
import '../../features/local_sharing/local_http/local_http_favorite_paths.dart';

class BrowserSettingsFormController {
  final homepageController = TextEditingController();
  final proxyHostController = TextEditingController();
  final proxyPortController = TextEditingController();
  final localProxyPortController = TextEditingController();
  final proxyUuidController = TextEditingController();
  final proxyServerNameController = TextEditingController();
  final proxyTransportPathController = TextEditingController();
  final proxyTransportHostController = TextEditingController();
  final proxyBypassDomainsController = TextEditingController();
  final localHttpRootPathController = TextEditingController();
  final localHttpPortController = TextEditingController();
  final localHttpUploadKeyController = TextEditingController();
  final nativeVideoParserApiController = TextEditingController();
  final desktopUserAgentController = TextEditingController();
  final nodeLinkController = TextEditingController();
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool proxyEnabled = false;
  bool localHttpServerEnabled = false;
  bool localHttpBindAllInterfaces = false;
  bool nativeVideoPlayerEnabled = false;
  bool proxyTlsEnabled = false;
  bool proxyTlsInsecure = false;
  bool openNewWindowInTab = true;
  bool webDebugConsoleEnabled = false;
  bool desktopModeEnabled = false;
  bool appCacheAutoClearEnabled = false;
  int appCacheAutoClearIntervalHours = 24;
  List<String> localHttpFavoriteRootPaths = const <String>[];

  String selectedProtocol = BrowserProxyProtocol.http;
  List<BrowserProxyNode> proxyNodes = const <BrowserProxyNode>[];
  String? selectedProxyNodeId;
  String proxyPacketEncoding = '';
  String selectedTransportType = '';

  void dispose() {
    homepageController.dispose();
    proxyHostController.dispose();
    proxyPortController.dispose();
    localProxyPortController.dispose();
    proxyUuidController.dispose();
    proxyServerNameController.dispose();
    proxyTransportPathController.dispose();
    proxyTransportHostController.dispose();
    proxyBypassDomainsController.dispose();
    localHttpRootPathController.dispose();
    localHttpPortController.dispose();
    localHttpUploadKeyController.dispose();
    nativeVideoParserApiController.dispose();
    desktopUserAgentController.dispose();
    nodeLinkController.dispose();
    revision.dispose();
  }

  void markDirty() {
    revision.value++;
  }

  void applySettings(BrowserSettings settings) {
    applyFormData(BrowserSettingsFormData.fromSettings(settings));
  }

  void applyProxyNode(BrowserProxyNode node) {
    selectedProtocol = node.proxyProtocol;
    proxyHostController.text = node.proxyHost;
    proxyPortController.text = node.proxyPort?.toString() ?? '';
    proxyUuidController.text = node.proxyUuid;
    proxyServerNameController.text = node.proxyServerName;
    proxyTransportPathController.text = node.proxyTransportPath;
    proxyTransportHostController.text = node.proxyTransportHost;
    selectedTransportType = node.proxyTransportType;
    proxyPacketEncoding = node.proxyPacketEncoding;
    proxyTlsEnabled = node.proxyTlsEnabled;
    proxyTlsInsecure = node.proxyTlsInsecure;
  }

  void applyFormData(BrowserSettingsFormData formData) {
    homepageController.text = formData.homepageUrl;
    proxyEnabled = formData.proxyEnabled;
    proxyHostController.text = formData.proxyHost;
    proxyPortController.text = formData.proxyPortText;
    localProxyPortController.text = formData.localProxyPortText;
    proxyUuidController.text = formData.proxyUuid;
    proxyServerNameController.text = formData.proxyServerName;
    proxyTransportPathController.text = formData.proxyTransportPath;
    proxyTransportHostController.text = formData.proxyTransportHost;
    proxyBypassDomainsController.text = formData.proxyBypassDomains;
    localHttpRootPathController.text = formData.localHttpRootPath;
    localHttpFavoriteRootPaths = List<String>.from(
      formData.localHttpFavoriteRootPaths,
    );
    localHttpPortController.text = formData.localHttpPortText;
    localHttpUploadKeyController.text = formData.localHttpUploadKey;
    nativeVideoParserApiController.text = formData.nativeVideoParserApiBaseUrl;
    desktopUserAgentController.text = formData.desktopUserAgentOverride;
    selectedProtocol = formData.selectedProtocol;
    proxyNodes = List<BrowserProxyNode>.from(formData.proxyNodes);
    selectedProxyNodeId = formData.selectedProxyNodeId;
    proxyPacketEncoding = formData.proxyPacketEncoding;
    selectedTransportType = formData.selectedTransportType;
    proxyTlsEnabled = formData.proxyTlsEnabled;
    proxyTlsInsecure = formData.proxyTlsInsecure;
    localHttpServerEnabled = formData.localHttpServerEnabled;
    localHttpBindAllInterfaces = formData.localHttpBindAllInterfaces;
    nativeVideoPlayerEnabled = formData.nativeVideoPlayerEnabled;
    openNewWindowInTab = formData.openNewWindowInTab;
    webDebugConsoleEnabled = formData.webDebugConsoleEnabled;
    desktopModeEnabled = formData.desktopModeEnabled;
    appCacheAutoClearEnabled = formData.appCacheAutoClearEnabled;
    appCacheAutoClearIntervalHours = formData.appCacheAutoClearIntervalHours;
  }

  BrowserSettingsFormData readFormData() {
    return BrowserSettingsFormData(
      homepageUrl: homepageController.text.trim().isEmpty
          ? 'https://www.google.com'
          : homepageController.text.trim(),
      proxyEnabled: proxyEnabled,
      proxyHost: proxyHostController.text.trim(),
      proxyPortText: proxyPortController.text.trim(),
      localProxyPortText: localProxyPortController.text.trim(),
      proxyUuid: proxyUuidController.text.trim(),
      proxyServerName: proxyServerNameController.text.trim(),
      proxyTransportPath: proxyTransportPathController.text.trim(),
      proxyTransportHost: proxyTransportHostController.text.trim(),
      proxyBypassDomains: proxyBypassDomainsController.text.trim(),
      proxyNodes: proxyNodes,
      selectedProxyNodeId: selectedProxyNodeId,
      localHttpRootPath: localHttpRootPathController.text.trim(),
      localHttpFavoriteRootPaths: localHttpFavoriteRootPaths,
      localHttpPortText: localHttpPortController.text.trim(),
      localHttpUploadKey: localHttpUploadKeyController.text.trim(),
      selectedProtocol: selectedProtocol,
      proxyPacketEncoding: proxyPacketEncoding,
      selectedTransportType: selectedTransportType,
      proxyTlsEnabled: proxyTlsEnabled,
      proxyTlsInsecure: proxyTlsInsecure,
      localHttpServerEnabled: localHttpServerEnabled,
      localHttpBindAllInterfaces: localHttpBindAllInterfaces,
      nativeVideoPlayerEnabled: nativeVideoPlayerEnabled,
      nativeVideoParserApiBaseUrl: nativeVideoParserApiController.text.trim(),
      openNewWindowInTab: openNewWindowInTab,
      webDebugConsoleEnabled: webDebugConsoleEnabled,
      desktopModeEnabled: desktopModeEnabled,
      desktopUserAgentOverride: desktopUserAgentController.text.trim(),
      appCacheAutoClearEnabled: appCacheAutoClearEnabled,
      appCacheAutoClearIntervalHours: appCacheAutoClearIntervalHours,
    );
  }

  BrowserSettings buildSettings() {
    return readFormData().toBrowserSettings();
  }

  bool addLocalHttpFavoriteRootPath(String path) {
    final normalized = normalizeLocalHttpFavoritePaths(<String>[path]);
    if (normalized.isEmpty ||
        localHttpFavoriteRootPaths.contains(normalized.first)) {
      return false;
    }
    localHttpFavoriteRootPaths = <String>[
      ...localHttpFavoriteRootPaths,
      normalized.first,
    ];
    return true;
  }

  bool removeLocalHttpFavoriteRootPath(String path) {
    final nextPaths = localHttpFavoriteRootPaths
        .where((favoritePath) => favoritePath != path)
        .toList(growable: false);
    if (nextPaths.length == localHttpFavoriteRootPaths.length) {
      return false;
    }
    localHttpFavoriteRootPaths = nextPaths;
    return true;
  }

  bool get showsUuidField =>
      selectedProtocol == BrowserProxyProtocol.http ||
      selectedProtocol == BrowserProxyProtocol.vless ||
      selectedProtocol == BrowserProxyProtocol.hysteria2;

  bool get showsTransportFields =>
      selectedProtocol == BrowserProxyProtocol.vless;

  bool get showsHysteria2ObfsFields =>
      selectedProtocol == BrowserProxyProtocol.hysteria2;

  bool get showsPacketEncodingField =>
      selectedProtocol == BrowserProxyProtocol.vless;

  bool get showsTlsFields =>
      selectedProtocol == BrowserProxyProtocol.vless ||
      selectedProtocol == BrowserProxyProtocol.hysteria2;
}
