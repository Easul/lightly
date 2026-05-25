import 'data_management_page.dart';

class BrowserPageDataManagementActionPlan {
  const BrowserPageDataManagementActionPlan({
    required this.reloadSettings,
    required this.showFavoritesHome,
    required this.refreshFavorites,
    required this.reloadCurrentWebView,
    required this.rebuild,
  });

  final bool reloadSettings;
  final bool showFavoritesHome;
  final bool refreshFavorites;
  final bool reloadCurrentWebView;
  final bool rebuild;

  bool get hasWorkToDo =>
      reloadSettings ||
      showFavoritesHome ||
      refreshFavorites ||
      reloadCurrentWebView ||
      rebuild;
}

class BrowserPageRouteHandler {
  const BrowserPageRouteHandler();

  bool shouldReloadSettingsAfterSettingsRoute(Object? result) {
    return result == true;
  }

  BrowserPageDataManagementActionPlan planDataManagementActions({
    required Object? result,
    required String currentUrl,
    required bool isFavoritesPage,
  }) {
    if (result is DataManagementPageResult && result.changed) {
      final shouldReloadCurrentWebView =
          result.webDataChanged && !isFavoritesPage;
      return BrowserPageDataManagementActionPlan(
        reloadSettings: true,
        showFavoritesHome: result.favoritesChanged,
        refreshFavorites: result.favoritesChanged,
        reloadCurrentWebView: shouldReloadCurrentWebView,
        rebuild: true,
      );
    }

    if (result == true) {
      return const BrowserPageDataManagementActionPlan(
        reloadSettings: true,
        showFavoritesHome: true,
        refreshFavorites: true,
        reloadCurrentWebView: false,
        rebuild: true,
      );
    }

    return const BrowserPageDataManagementActionPlan(
      reloadSettings: false,
      showFavoritesHome: false,
      refreshFavorites: false,
      reloadCurrentWebView: false,
      rebuild: false,
    );
  }
}
