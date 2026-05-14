import 'browser_tab_coordinator.dart';
import 'browser_tab_service.dart';

class BrowserFavoritesCoordinator {
  const BrowserFavoritesCoordinator({
    this.favoritesPageUrl = 'ruoqing://favorites',
  });

  final String favoritesPageUrl;

  bool isFavoritesPage(String? url) => url == favoritesPageUrl;

  void applyFavoritesHomeState({
    required BrowserTabCoordinator tabCoordinator,
    required BrowserTabService tabService,
  }) {
    final activeTabId = tabCoordinator.activeTabId;
    if (activeTabId != null) {
      tabService.resetKeepAlive(activeTabId);
    }
    tabCoordinator.updateActiveTab(
      url: favoritesPageUrl,
      title: '',
      isLoading: false,
      canGoBack: false,
      canGoForward: false,
      scrollPosition: 0,
    );
  }
}
