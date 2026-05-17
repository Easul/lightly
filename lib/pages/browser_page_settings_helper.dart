import '../browser/browser_settings.dart';

class BrowserPageSettingsSnapshot {
  const BrowserPageSettingsSnapshot({
    required this.settings,
    required this.proxySupported,
    required this.isProxyActive,
    required this.statusMessage,
    required this.isInitialized,
  });

  final BrowserSettings settings;
  final bool proxySupported;
  final bool isProxyActive;
  final String statusMessage;
  final bool isInitialized;
}

class BrowserPageSettingsHelper {
  const BrowserPageSettingsHelper();

  BrowserPageSettingsSnapshot buildInitializedSnapshot({
    required BrowserSettings settings,
    required bool proxySupported,
    required bool isProxyActive,
    required String statusMessage,
  }) {
    return BrowserPageSettingsSnapshot(
      settings: settings,
      proxySupported: proxySupported,
      isProxyActive: isProxyActive,
      statusMessage: statusMessage,
      isInitialized: true,
    );
  }

  BrowserPageSettingsSnapshot buildReloadedSnapshot({
    required BrowserSettings settings,
    required bool proxySupported,
    required bool isProxyActive,
    required String statusMessage,
    required bool isInitialized,
  }) {
    return BrowserPageSettingsSnapshot(
      settings: settings,
      proxySupported: proxySupported,
      isProxyActive: isProxyActive,
      statusMessage: statusMessage,
      isInitialized: isInitialized,
    );
  }
}
