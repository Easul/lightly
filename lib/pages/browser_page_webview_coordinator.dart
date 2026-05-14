enum BrowserPageWebViewErrorAction {
  blockedByResponse,
  externalScheme,
  description,
}

class BrowserPageWebViewErrorDecision {
  const BrowserPageWebViewErrorDecision({
    required this.action,
    required this.statusMessage,
  });

  final BrowserPageWebViewErrorAction action;
  final String statusMessage;
}

class BrowserPageWebViewCoordinator {
  const BrowserPageWebViewCoordinator();

  bool shouldClearStatusOnLoadStart({
    required bool isActiveTab,
    required String currentStatusMessage,
    required bool didChangeProgress,
    required bool didChangeLoading,
  }) {
    return isActiveTab &&
        (currentStatusMessage.isNotEmpty ||
            didChangeProgress ||
            didChangeLoading);
  }

  bool shouldRebuildOnLoadStop({
    required bool isActiveTab,
    required bool didChangeProgress,
    required bool didChangeTitle,
    required bool didChangeLoading,
  }) {
    return isActiveTab &&
        (didChangeProgress || didChangeTitle || didChangeLoading);
  }

  bool shouldRebuildOnTitleChanged({
    required bool isActiveTab,
    required bool didChangeTitle,
  }) {
    return isActiveTab && didChangeTitle;
  }

  BrowserPageWebViewErrorDecision decideErrorStatus({
    required String description,
    required String blockedPopupStatus,
    required String externalSchemeStatus,
  }) {
    if (description.contains('ERR_BLOCKED_BY_RESPONSE')) {
      return BrowserPageWebViewErrorDecision(
        action: BrowserPageWebViewErrorAction.blockedByResponse,
        statusMessage: blockedPopupStatus,
      );
    }
    if (description.contains('ERR_UNKNOWN_URL_SCHEME')) {
      return BrowserPageWebViewErrorDecision(
        action: BrowserPageWebViewErrorAction.externalScheme,
        statusMessage: externalSchemeStatus,
      );
    }
    return BrowserPageWebViewErrorDecision(
      action: BrowserPageWebViewErrorAction.description,
      statusMessage: description,
    );
  }

  bool shouldHandleVisitedHistoryForActiveTab({required bool isActiveTab}) {
    return isActiveTab;
  }

  bool shouldSyncVisitedHistoryForBackgroundTab({
    required bool isActiveTab,
    required bool isFavoritesPage,
    required bool isWebScheme,
  }) {
    return !isActiveTab && !isFavoritesPage && isWebScheme;
  }
}
