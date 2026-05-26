import '../browser/browser_settings.dart';
import '../browser/models/browser_tab_session.dart';
import '../browser/services/browser_favorites_coordinator.dart';
import '../browser/services/browser_video_player_coordinator.dart';
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
    // If the tab has already loaded real content (non-blank URL), never
    // force a reload of the initial URL — the WebView can recover via
    // keepAlive or a fresh InAppWebView with no initialUrlRequest.
    // Only brand-new tabs (about:blank or empty URL) should load the
    // initial URL request.
    if (tab.url.isNotEmpty && tab.url != 'about:blank') {
      return false;
    }
    // For tabs that have never loaded real content, load the initial URL
    // unless a retained WebView is still attached.
    return !(tab.hasAttachedWebView && tab.keepAlive != null);
  }

  bool shouldOpenNativeVideoFromUrl({
    required BrowserVideoPlayerCoordinator videoPlayerCoordinator,
    required String url,
    required BrowserSettings settings,
  }) {
    return videoPlayerCoordinator.shouldOpenNativeVideoFromUrl(url, settings);
  }

  bool shouldUseProxy({
    required BrowserSettings settings,
    required bool proxySupported,
  }) {
    return settings.shouldApplyProxy && proxySupported;
  }
}
