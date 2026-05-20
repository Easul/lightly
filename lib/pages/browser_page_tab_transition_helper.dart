import 'dart:async';

class BrowserPageTabTransitionDeps {
  const BrowserPageTabTransitionDeps({
    required this.detachCurrentController,
    required this.unfocusAddressBar,
    required this.syncAddressBar,
    required this.checkFavoriteStatus,
    required this.resetProgress,
  });

  final void Function() detachCurrentController;
  final void Function() unfocusAddressBar;
  final void Function() syncAddressBar;
  final Future<void> Function(String url) checkFavoriteStatus;
  final void Function() resetProgress;
}

class BrowserPageTabTransitionHelper {
  const BrowserPageTabTransitionHelper();

  Future<void> prepareOpenedOrSwitchedTab({
    required BrowserPageTabTransitionDeps deps,
    required void Function() resetVideoDetectionState,
    required String url,
    required void Function() applyStatusAfterTransition,
    required void Function() syncTrackedScrollPosition,
    required bool syncTrackedScroll,
  }) async {
    deps.detachCurrentController();
    deps.unfocusAddressBar();
    resetVideoDetectionState();
    if (syncTrackedScroll) {
      syncTrackedScrollPosition();
    }
    deps.syncAddressBar();
    await deps.checkFavoriteStatus(url);
    deps.resetProgress();
    applyStatusAfterTransition();
  }

  Future<void> prepareClosedTab({
    required BrowserPageTabTransitionDeps deps,
    required String url,
    required void Function() applyStatusAfterTransition,
  }) async {
    deps.detachCurrentController();
    deps.unfocusAddressBar();
    deps.syncAddressBar();
    await deps.checkFavoriteStatus(url);
    deps.resetProgress();
    applyStatusAfterTransition();
  }

  Future<void> prepareCloseAllTabs({
    required BrowserPageTabTransitionDeps deps,
    required String url,
    required void Function() applyStatusAfterTransition,
  }) async {
    deps.unfocusAddressBar();
    deps.syncAddressBar();
    await deps.checkFavoriteStatus(url);
    deps.resetProgress();
    applyStatusAfterTransition();
  }
}
