import 'browser_page_route_handler.dart';

class BrowserPageActionCoordinator {
  const BrowserPageActionCoordinator();

  bool canShowFindInPage({
    required bool isFindAvailable,
    required bool isFavoritesPage,
  }) {
    return isFindAvailable && !isFavoritesPage;
  }

  Future<void> applyDataManagementPlan({
    required BrowserPageDataManagementActionPlan plan,
    required Future<void> Function() reloadSettings,
    required Future<void> Function() showFavoritesHome,
    required Future<void> Function() refreshFavorites,
    required Future<void> Function() reloadCurrentWebView,
    required void Function() rebuild,
  }) async {
    if (!plan.hasWorkToDo) {
      return;
    }
    if (plan.reloadSettings) {
      await reloadSettings();
    }
    if (plan.showFavoritesHome) {
      await showFavoritesHome();
    }
    if (plan.refreshFavorites) {
      await refreshFavorites();
    }
    if (plan.reloadCurrentWebView) {
      await reloadCurrentWebView();
    }
    if (plan.rebuild) {
      rebuild();
    }
  }
}
