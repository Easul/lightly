import 'dart:async';

import 'package:flutter/foundation.dart';

typedef BrowserOverlayReload = void Function(String url);

class BrowserPageOverlayLoadFreezeCoordinator {
  BrowserPageOverlayLoadFreezeCoordinator({
    this.freezeDelay = const Duration(milliseconds: 800),
  });

  final Duration freezeDelay;

  Timer? _freezeTimer;
  String? _stoppedTabId;
  String? _stoppedUrl;

  void schedule({
    required bool Function() isMounted,
    required bool Function() hasOpenOverlay,
    required String? Function() activeTabId,
    required String Function() currentUrl,
    required bool Function() isLoading,
    required bool Function(String url) isFavoritesPage,
    required VoidCallback stopLoading,
  }) {
    _cancelPendingTimer();
    final initialTabId = activeTabId();
    if (initialTabId == null ||
        !isMounted() ||
        !hasOpenOverlay() ||
        !isLoading() ||
        isFavoritesPage(currentUrl())) {
      return;
    }

    _freezeTimer = Timer(freezeDelay, () {
      _freezeTimer = null;
      final currentTabId = activeTabId();
      final url = currentUrl();
      if (!isMounted() ||
          !hasOpenOverlay() ||
          currentTabId != initialTabId ||
          !isLoading() ||
          isFavoritesPage(url)) {
        return;
      }

      _stoppedTabId = currentTabId;
      _stoppedUrl = url;
      stopLoading();
    });
  }

  void resume({
    required bool Function() isMounted,
    required String? Function() activeTabId,
    required String Function() currentUrl,
    required bool Function(String url) isFavoritesPage,
    required BrowserOverlayReload reload,
  }) {
    _cancelPendingTimer();
    final stoppedTabId = _stoppedTabId;
    final stoppedUrl = _stoppedUrl;
    _stoppedTabId = null;
    _stoppedUrl = null;

    if (stoppedTabId == null ||
        stoppedUrl == null ||
        !isMounted() ||
        activeTabId() != stoppedTabId ||
        currentUrl() != stoppedUrl ||
        isFavoritesPage(stoppedUrl)) {
      return;
    }

    reload(stoppedUrl);
  }

  void cancel() {
    _cancelPendingTimer();
    _stoppedTabId = null;
    _stoppedUrl = null;
  }

  void _cancelPendingTimer() {
    _freezeTimer?.cancel();
    _freezeTimer = null;
  }
}
