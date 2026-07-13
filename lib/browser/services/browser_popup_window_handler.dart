import 'package:flutter/material.dart';

import '../utils/browser_auth_url_detector.dart';
import '../utils/browser_popup_filter.dart';
import '../utils/browser_popup_url_decoder.dart';
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
  int _popupDialogCount = 0;

  bool get isShowingPopupDialog => _popupDialogCount > 0;

  BrowserPopupWindowDecision decide({
    required String requestedUrl,
    required String? sourceUrl,
    required bool hasGesture,
    required bool openNewWindowInTab,
  }) {
    final decodedRequestedUrl = BrowserPopupUrlDecoder.decodeIfNeeded(
      requestedUrl,
    );
    final parsedRequestedUrl = decodedRequestedUrl.isEmpty
        ? null
        : Uri.tryParse(decodedRequestedUrl);
    final requestedScheme = parsedRequestedUrl?.scheme.toLowerCase();

    if (parsedRequestedUrl != null &&
        !BrowserPopupFilter.isWebScheme(requestedScheme)) {
      return BrowserPopupWindowDecision(
        action: BrowserPopupWindowAction.external,
        initialUrl: decodedRequestedUrl,
      );
    }

    if (decodedRequestedUrl.isEmpty &&
        hasGesture &&
        BrowserAuthUrlDetector.looksLikeAuthUrl(sourceUrl)) {
      return const BrowserPopupWindowDecision(
        action: BrowserPopupWindowAction.openTab,
        statusMessage: '站点正在延迟创建登录窗口，已改为新标签页继续',
      );
    }

    if (decodedRequestedUrl.isEmpty && hasGesture && openNewWindowInTab) {
      return const BrowserPopupWindowDecision(
        action: BrowserPopupWindowAction.openTab,
      );
    }

    if (BrowserPopupFilter.shouldSuppressPopupUrl(decodedRequestedUrl)) {
      return const BrowserPopupWindowDecision(
        action: BrowserPopupWindowAction.ignore,
      );
    }

    final isTrustedAuthPopup = BrowserAuthUrlDetector.isTrustedAuthPopupUrl(
      decodedRequestedUrl,
    );
    if (openNewWindowInTab || isTrustedAuthPopup) {
      return BrowserPopupWindowDecision(
        action: BrowserPopupWindowAction.openTab,
        initialUrl: decodedRequestedUrl,
      );
    }

    return BrowserPopupWindowDecision(
      action: BrowserPopupWindowAction.showPopup,
      initialUrl: decodedRequestedUrl.isEmpty ? null : decodedRequestedUrl,
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
