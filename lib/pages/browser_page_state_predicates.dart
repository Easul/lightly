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
    return !(tab?.hasAttachedWebView == true && tab?.keepAlive != null);
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
