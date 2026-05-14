enum BrowserPageBackAction {
  exitVideoFullscreen,
  closeVideoOverlay,
  exitWebFullscreen,
  goBackInWebView,
  closeActiveTab,
  showFavoritesHome,
  exitApp,
}

class BrowserPageBackDecision {
  const BrowserPageBackDecision({required this.action, this.activeTabId});

  final BrowserPageBackAction action;
  final String? activeTabId;
}

enum BrowserPageCloseTabFollowUp { switchToTab, rebuild }

class BrowserPageCloseTabDecision {
  const BrowserPageCloseTabDecision({
    required this.nextTabId,
    required this.followUp,
  });

  final String nextTabId;
  final BrowserPageCloseTabFollowUp followUp;
}

class BrowserPageTabFlowCoordinator {
  const BrowserPageTabFlowCoordinator();

  BrowserPageBackDecision decideBackAction({
    required bool hasActiveVideoOverlay,
    required bool isVideoFullscreen,
    required bool isInWebFullscreen,
    required bool canGoBackInWebView,
    required int tabCount,
    required String? activeTabId,
    required bool isFavoritesPage,
  }) {
    if (hasActiveVideoOverlay) {
      return BrowserPageBackDecision(
        action: isVideoFullscreen
            ? BrowserPageBackAction.exitVideoFullscreen
            : BrowserPageBackAction.closeVideoOverlay,
      );
    }
    if (isInWebFullscreen) {
      return const BrowserPageBackDecision(
        action: BrowserPageBackAction.exitWebFullscreen,
      );
    }
    if (canGoBackInWebView) {
      return const BrowserPageBackDecision(
        action: BrowserPageBackAction.goBackInWebView,
      );
    }
    if (tabCount > 1 && activeTabId != null) {
      return BrowserPageBackDecision(
        action: BrowserPageBackAction.closeActiveTab,
        activeTabId: activeTabId,
      );
    }
    if (!isFavoritesPage) {
      return const BrowserPageBackDecision(
        action: BrowserPageBackAction.showFavoritesHome,
      );
    }
    return const BrowserPageBackDecision(action: BrowserPageBackAction.exitApp);
  }

  BrowserPageCloseTabDecision decideCloseTabFollowUp({
    required String previousActiveId,
    required String nextTabId,
  }) {
    return BrowserPageCloseTabDecision(
      nextTabId: nextTabId,
      followUp: previousActiveId != nextTabId
          ? BrowserPageCloseTabFollowUp.switchToTab
          : BrowserPageCloseTabFollowUp.rebuild,
    );
  }

  bool shouldShowFavoritesInsteadOfLoading({required bool isFavoritesPage}) {
    return isFavoritesPage;
  }
}
