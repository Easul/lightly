import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../browser_settings.dart';
import '../models/browser_settings_form_data.dart';

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
  final nodeLinkController = TextEditingController();
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool proxyEnabled = false;
  bool localHttpServerEnabled = false;
  bool localHttpBindAllInterfaces = false;
  bool nativeVideoPlayerEnabled = false;
  bool proxyTlsEnabled = false;
  bool proxyTlsInsecure = false;
  bool openNewWindowInTab = true;

  String selectedProtocol = BrowserProxyProtocol.http;
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
    nodeLinkController.dispose();
    revision.dispose();
  }

  void markDirty() {
    revision.value++;
  }

  void applySettings(BrowserSettings settings) {
    applyFormData(BrowserSettingsFormData.fromSettings(settings));
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
    localHttpPortController.text = formData.localHttpPortText;
    localHttpUploadKeyController.text = formData.localHttpUploadKey;
    nativeVideoParserApiController.text = formData.nativeVideoParserApiBaseUrl;
    selectedProtocol = formData.selectedProtocol;
    proxyPacketEncoding = formData.proxyPacketEncoding;
    selectedTransportType = formData.selectedTransportType;
    proxyTlsEnabled = formData.proxyTlsEnabled;
    proxyTlsInsecure = formData.proxyTlsInsecure;
    localHttpServerEnabled = formData.localHttpServerEnabled;
    localHttpBindAllInterfaces = formData.localHttpBindAllInterfaces;
    nativeVideoPlayerEnabled = formData.nativeVideoPlayerEnabled;
    openNewWindowInTab = formData.openNewWindowInTab;
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
      localHttpRootPath: localHttpRootPathController.text.trim(),
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
    );
  }

  BrowserSettings buildSettings() {
    return readFormData().toBrowserSettings();
  }

  bool get showsUuidField =>
      selectedProtocol == BrowserProxyProtocol.http ||
      selectedProtocol == BrowserProxyProtocol.vless ||
      selectedProtocol == BrowserProxyProtocol.hysteria2;

  bool get showsTransportFields =>
      selectedProtocol == BrowserProxyProtocol.vless;

  bool get showsTlsFields =>
      selectedProtocol == BrowserProxyProtocol.vless ||
      selectedProtocol == BrowserProxyProtocol.hysteria2;
}
