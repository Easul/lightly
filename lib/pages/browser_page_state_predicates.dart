import '../browser/browser_settings.dart';
import '../browser/models/browser_tab_session.dart';
import '../browser/services/browser_favorites_coordinator.dart';
import '../browser/utils/browser_url_utils.dart';

class BrowserPageStatePredicates {
  const BrowserPageStatePredicates();

  bool isFavoritesPage({
    required BrowserFavoritesCoordinator favoritesCoordinator,
    required String? url,
  }) {
    return favoritesCoordinator.isFavoritesPage(url);
  }

  bool shouldPauseCurrentWebViewOnTabSwitch(String url) {
    return isLocalBrowserUrl(url);
  }

  bool shouldLoadInitialUrlForTab(BrowserTabSession? tab) {
    if (tab == null) return true;
    // Once a WebView has attached, avoid re-sending the initial URL during
    // rebuilds so auth popups and the current page keep their live content.
    if (tab.hasAttachedWebView) {
      return false;
    }
    // Restored or trimmed tabs have a saved URL but no attached WebView yet;
    // they still need an initialUrlRequest to render instead of a blank page.
    return true;
  }

  bool shouldRebuildAfterAddressLoad({required bool wasFavoritesPage}) {
    return wasFavoritesPage;
  }

  bool canShowYoutubeScrollPlayButton({
    required String url,
    required BrowserSettings settings,
  }) {
    if (!settings.canResolveYoutubeWithNativePlayer) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == 'm.youtube.com' &&
        uri.path == '/watch' &&
        (uri.queryParameters['v']?.trim().isNotEmpty ?? false);
  }

  bool shouldRevealYoutubeScrollPlayButton({
    required double previousY,
    required double nextY,
    required bool isEligible,
    double threshold = 32,
  }) {
    return isEligible && nextY - previousY >= threshold;
  }

  bool shouldHideYoutubeScrollPlayButton({
    required double previousY,
    required double nextY,
    required bool isEligible,
    double threshold = 32,
  }) {
    return !isEligible || previousY - nextY >= threshold;
  }

  bool shouldUseProxy({
    required BrowserSettings settings,
    required bool proxySupported,
  }) {
    return settings.shouldApplyProxy && proxySupported;
  }
}
