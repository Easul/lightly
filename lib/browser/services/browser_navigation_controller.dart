import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../utils/browser_popup_filter.dart';

typedef BrowserNavigationUrlSync = void Function(String url);
typedef BrowserNavigationRefresh = Future<void> Function();
typedef BrowserExternalUrlConfirmation = Future<void> Function(Uri url);

class BrowserNavigationController {
  const BrowserNavigationController();

  Future<NavigationActionPolicy> handleNavigationRequest({
    required Uri? requestedUrl,
    required bool isExternalDialogShowing,
    required BrowserNavigationUrlSync syncUrl,
    required BrowserExternalUrlConfirmation confirmExternalUrl,
  }) async {
    if (requestedUrl == null) {
      return NavigationActionPolicy.ALLOW;
    }

    final scheme = requestedUrl.scheme.toLowerCase();
    if (BrowserPopupFilter.isWebScheme(scheme)) {
      syncUrl(requestedUrl.toString());
      return NavigationActionPolicy.ALLOW;
    }

    if (isExternalDialogShowing) {
      return NavigationActionPolicy.CANCEL;
    }

    await confirmExternalUrl(requestedUrl);
    return NavigationActionPolicy.CANCEL;
  }

  Future<void> handleVisitedHistoryUpdate({
    required Uri? requestedUrl,
    required bool shouldHandle,
    required BrowserNavigationUrlSync syncUrl,
    required BrowserNavigationRefresh refreshNavigation,
    required BrowserExternalUrlConfirmation confirmExternalUrl,
  }) async {
    if (requestedUrl == null || !shouldHandle) {
      return;
    }

    if (BrowserPopupFilter.isWebScheme(requestedUrl.scheme)) {
      syncUrl(requestedUrl.toString());
      await refreshNavigation();
      return;
    }

    unawaited(confirmExternalUrl(requestedUrl));
  }
}
