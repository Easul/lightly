import 'package:flutter/material.dart';

import '../utils/browser_auth_url_detector.dart';
import '../utils/browser_popup_filter.dart';
import '../widgets/popup_webview_dialog.dart';

enum BrowserPopupWindowAction { ignore, external, openTab, showPopup }

class BrowserPopupWindowDecision {
  const BrowserPopupWindowDecision({
    required this.action,
    this.statusMessage,
    this.initialUrl,
  });

  final BrowserPopupWindowAction action;
  final String? statusMessage;
  final String? initialUrl;
}

class BrowserPopupWindowHandler {
  static const Set<String> _popupRequiredAuthHosts = {'agentrouter.org'};

  int _popupDialogCount = 0;

  bool get isShowingPopupDialog => _popupDialogCount > 0;

  BrowserPopupWindowDecision decide({
    required String requestedUrl,
    required String? sourceUrl,
    required bool hasGesture,
    required bool openNewWindowInTab,
  }) {
    final parsedRequestedUrl = requestedUrl.isEmpty
        ? null
        : Uri.tryParse(requestedUrl);
    final requestedScheme = parsedRequestedUrl?.scheme.toLowerCase();

    if (parsedRequestedUrl != null &&
        !BrowserPopupFilter.isWebScheme(requestedScheme)) {
      return const BrowserPopupWindowDecision(
        action: BrowserPopupWindowAction.external,
      );
    }

    if (_shouldPreservePopupWindow(sourceUrl) ||
        _shouldPreservePopupWindow(requestedUrl)) {
      return BrowserPopupWindowDecision(
        action: BrowserPopupWindowAction.showPopup,
        initialUrl: requestedUrl.isEmpty ? null : requestedUrl,
      );
    }

    if (requestedUrl.isEmpty &&
        hasGesture &&
        BrowserAuthUrlDetector.looksLikeAuthUrl(sourceUrl)) {
      return const BrowserPopupWindowDecision(
        action: BrowserPopupWindowAction.openTab,
        statusMessage: '站点正在延迟创建登录窗口，已改为新标签页继续',
      );
    }

    if (requestedUrl.isEmpty && hasGesture && openNewWindowInTab) {
      if (_shouldPreservePopupWindow(sourceUrl)) {
        return const BrowserPopupWindowDecision(
          action: BrowserPopupWindowAction.showPopup,
        );
      }
      return const BrowserPopupWindowDecision(
        action: BrowserPopupWindowAction.openTab,
      );
    }

    if (BrowserPopupFilter.shouldSuppressPopupUrl(requestedUrl)) {
      return const BrowserPopupWindowDecision(
        action: BrowserPopupWindowAction.ignore,
      );
    }

    final isTrustedAuthPopup = BrowserAuthUrlDetector.isTrustedAuthPopupUrl(
      requestedUrl,
    );
    if (openNewWindowInTab || isTrustedAuthPopup) {
      return BrowserPopupWindowDecision(
        action: BrowserPopupWindowAction.openTab,
        initialUrl: requestedUrl,
      );
    }

    return BrowserPopupWindowDecision(
      action: BrowserPopupWindowAction.showPopup,
      initialUrl: requestedUrl.isEmpty ? null : requestedUrl,
    );
  }

  bool _shouldPreservePopupWindow(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null || host.isEmpty) {
      return false;
    }
    return _popupRequiredAuthHosts.any(
      (authHost) => host == authHost || host.endsWith('.$authHost'),
    );
  }

  Future<void> showPopupWindow({
    required BuildContext context,
    required int? windowId,
    required String? initialUrl,
    required void Function(String) onStatus,
  }) async {
    _popupDialogCount += 1;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) =>
            PopupWebViewDialog(windowId: windowId, initialUrl: initialUrl),
      );
    } finally {
      _popupDialogCount -= 1;
      if (_popupDialogCount <= 0) {
        _popupDialogCount = 0;
        onStatus('');
      }
    }
  }
}
