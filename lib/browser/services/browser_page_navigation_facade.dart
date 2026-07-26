import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../utils/browser_popup_filter.dart';
import 'browser_external_app_handler.dart';
import 'browser_external_url_launcher_service.dart';
import 'browser_navigation_controller.dart';
import 'browser_popup_raw_url_resolver.dart';
import 'browser_popup_window_handler.dart';

class BrowserPageNavigationFacade {
  BrowserPageNavigationFacade({
    BrowserNavigationController navigationController =
        const BrowserNavigationController(),
    BrowserPopupRawUrlResolver? popupRawUrlResolver,
    BrowserPopupWindowHandler? popupWindowHandler,
    BrowserExternalAppHandler? externalAppHandler,
    BrowserExternalUrlLauncherService? externalUrlLauncher,
  }) : _navigationController = navigationController,
       _popupRawUrlResolver =
           popupRawUrlResolver ?? BrowserPopupRawUrlResolver(),
       _popupWindowHandler = popupWindowHandler ?? BrowserPopupWindowHandler(),
       _externalAppHandler = externalAppHandler ?? BrowserExternalAppHandler(),
       _externalUrlLauncher =
           externalUrlLauncher ?? BrowserExternalUrlLauncherService();

  final BrowserNavigationController _navigationController;
  final BrowserPopupRawUrlResolver _popupRawUrlResolver;
  final BrowserPopupWindowHandler _popupWindowHandler;
  final BrowserExternalAppHandler _externalAppHandler;
  final BrowserExternalUrlLauncherService _externalUrlLauncher;

  void recordCapturedPopupUrl(String rawUrl) {
    _popupRawUrlResolver.recordCapturedUrl(rawUrl);
  }

  Future<BrowserPopupWindowDecision> resolvePopupWindow({
    required String fallbackUrl,
    required String? sourceUrl,
    required bool hasGesture,
    required bool openNewWindowInTab,
    required BrowserPopupJavascriptEvaluator evaluateJavascript,
  }) async {
    final requestedUrl = await _popupRawUrlResolver.resolve(
      fallbackUrl: fallbackUrl,
      evaluateJavascript: evaluateJavascript,
    );
    return _popupWindowHandler.decide(
      requestedUrl: requestedUrl,
      sourceUrl: sourceUrl,
      hasGesture: hasGesture,
      openNewWindowInTab: openNewWindowInTab,
    );
  }

  Future<void> showPopupWindow({
    required BuildContext context,
    required int? windowId,
    required String? initialUrl,
    required void Function(String message) onStatus,
  }) {
    return _popupWindowHandler.showPopupWindow(
      context: context,
      windowId: windowId,
      initialUrl: initialUrl,
      onStatus: onStatus,
    );
  }

  Future<String?> handleBlockedByResponse(
    BuildContext context,
    Uri? requestedUrl,
  ) {
    return _externalAppHandler.handleBlockedByResponse(
      context,
      requestedUrl,
      shouldSuppressPopupUrl: BrowserPopupFilter.shouldSuppressPopupUrl,
      launchExternalUrl: _externalUrlLauncher.launch,
    );
  }

  Future<String?> confirmAndLaunchExternalUrl(
    BuildContext context,
    Uri requestedUrl,
  ) {
    return _externalAppHandler.confirmAndLaunchExternalUrl(
      context,
      requestedUrl,
      launchExternalUrl: _externalUrlLauncher.launch,
    );
  }

  Future<NavigationActionPolicy> handleNavigationRequest({
    required Uri? requestedUrl,
    required BrowserNavigationUrlSync syncUrl,
    required BrowserExternalUrlConfirmation confirmExternalUrl,
  }) {
    return _navigationController.handleNavigationRequest(
      requestedUrl: requestedUrl,
      isExternalDialogShowing: _externalAppHandler.isShowingExternalAppDialog,
      syncUrl: syncUrl,
      confirmExternalUrl: confirmExternalUrl,
    );
  }

  Future<void> handleVisitedHistoryUpdate({
    required Uri? requestedUrl,
    required bool shouldHandle,
    required BrowserNavigationUrlSync syncUrl,
    required BrowserNavigationRefresh refreshNavigation,
    required BrowserExternalUrlConfirmation confirmExternalUrl,
  }) {
    return _navigationController.handleVisitedHistoryUpdate(
      requestedUrl: requestedUrl,
      shouldHandle: shouldHandle,
      syncUrl: syncUrl,
      refreshNavigation: refreshNavigation,
      confirmExternalUrl: confirmExternalUrl,
    );
  }
}
