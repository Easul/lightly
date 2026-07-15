import 'dart:async';

class BrowserWebViewEventController {
  const BrowserWebViewEventController();

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
    required bool didChangeLoading,
  }) {
    return isActiveTab && (didChangeProgress || didChangeLoading);
  }

  void handleError({
    required String? hostedTabId,
    required bool isMounted,
    required bool isActiveTab,
    required Uri requestedUrl,
    required String description,
    required String blockedPopupStatus,
    required String externalSchemeStatus,
    required bool requestedUrlIsWebScheme,
    required void Function() endRefreshing,
    required void Function(String tabId) markTabNotLoading,
    required Future<void> Function(Uri? url) handleBlockedByResponse,
    required Future<void> Function(Uri url) confirmExternalUrl,
    required void Function(String status) setStatus,
  }) {
    if (hostedTabId == null || !isMounted) {
      return;
    }

    endRefreshing();
    markTabNotLoading(hostedTabId);
    if (!isActiveTab) {
      return;
    }

    if (description.contains('ERR_BLOCKED_BY_RESPONSE')) {
      unawaited(handleBlockedByResponse(requestedUrl));
      setStatus(blockedPopupStatus);
      return;
    }

    if (description.contains('ERR_UNKNOWN_URL_SCHEME')) {
      if (!requestedUrlIsWebScheme) {
        unawaited(confirmExternalUrl(requestedUrl));
      }
      setStatus(externalSchemeStatus);
      return;
    }

    setStatus(description);
  }

  void handleVisitedHistory({
    required String? hostedTabId,
    required bool isFavoritesPage,
    required bool isActiveTab,
    required Uri? url,
    required bool isWebScheme,
    required Future<void> Function() recordCookieOrigin,
    required void Function() scheduleActiveRefresh,
    required void Function(String tabId, String url) updateBackgroundTabUrl,
  }) {
    if (hostedTabId == null || isFavoritesPage) {
      return;
    }

    if (isActiveTab) {
      unawaited(recordCookieOrigin());
      scheduleActiveRefresh();
      return;
    }

    if (url != null && isWebScheme) {
      updateBackgroundTabUrl(hostedTabId, url.toString());
    }
  }
}
