import 'dart:async';

class BrowserPageTabTransitionHelper {
  const BrowserPageTabTransitionHelper();

  Future<void> prepareOpenedOrSwitchedTab({
    required void Function() clearWebViewController,
    required void Function() unfocusAddressBar,
    required void Function() resetVideoDetectionState,
    required void Function() syncAddressBar,
    required Future<void> Function(String url) checkFavoriteStatus,
    required String url,
    required void Function() resetProgress,
    required void Function() clearStatus,
    required void Function() syncTrackedScrollPosition,
    required bool syncTrackedScroll,
  }) async {
    clearWebViewController();
    unfocusAddressBar();
    resetVideoDetectionState();
    if (syncTrackedScroll) {
      syncTrackedScrollPosition();
    }
    syncAddressBar();
    await checkFavoriteStatus(url);
    resetProgress();
    clearStatus();
  }

  Future<void> prepareClosedTab({
    required void Function() clearWebViewController,
    required void Function() unfocusAddressBar,
    required void Function() syncAddressBar,
    required Future<void> Function(String url) checkFavoriteStatus,
    required String url,
    required void Function() resetProgress,
    required void Function() clearStatus,
  }) async {
    clearWebViewController();
    unfocusAddressBar();
    syncAddressBar();
    await checkFavoriteStatus(url);
    resetProgress();
    clearStatus();
  }

  Future<void> prepareCloseAllTabs({
    required void Function() unfocusAddressBar,
    required void Function() syncAddressBar,
    required Future<void> Function(String url) checkFavoriteStatus,
    required String url,
    required void Function() resetProgress,
    required void Function() clearStatus,
  }) async {
    unfocusAddressBar();
    syncAddressBar();
    await checkFavoriteStatus(url);
    resetProgress();
    clearStatus();
  }
}
