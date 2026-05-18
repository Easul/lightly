import 'browser_tab_coordinator.dart';

class BrowserFavoritesCoordinator {
  const BrowserFavoritesCoordinator({
    this.favoritesPageUrl = 'ruoqing://favorites',
  });

  final String favoritesPageUrl;

  bool isFavoritesPage(String? url) => url == favoritesPageUrl;

  void applyFavoritesHomeState({
    required BrowserTabCoordinator tabCoordinator,
  }) {
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
