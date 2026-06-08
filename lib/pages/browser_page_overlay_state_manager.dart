import 'dart:async';

import 'package:flutter/foundation.dart';

import 'browser_page_lifecycle_coordinator.dart';

class BrowserPageOverlayStateManager {
  BrowserPageOverlayStateManager({
    required BrowserPageLifecycleCoordinator coordinator,
    required bool Function() isMounted,
    required VoidCallback syncNotifiers,
    required VoidCallback rebuild,
    required void Function({required bool trimKeepAlives}) pauseWebView,
    required VoidCallback resumeWebView,
  }) : _coordinator = coordinator,
       _isMounted = isMounted,
       _syncNotifiers = syncNotifiers,
       _rebuild = rebuild,
       _pauseWebView = pauseWebView,
       _resumeWebView = resumeWebView;

  final BrowserPageLifecycleCoordinator _coordinator;
  final bool Function() _isMounted;
  final VoidCallback _syncNotifiers;
  final VoidCallback _rebuild;
  final void Function({required bool trimKeepAlives}) _pauseWebView;
  final VoidCallback _resumeWebView;

  int _overlayDepth = 0;
  Timer? _overlaySettledTimer;
  bool _hasDeferredOverlayRebuild = false;
  bool _disposed = false;

  bool get shouldSkipRebuild =>
      _coordinator.shouldSkipRebuild(overlayDepth: _overlayDepth) ||
      _overlaySettledTimer != null;

  bool get shouldFreezeWebView =>
      _overlayDepth > 0 || _overlaySettledTimer != null;

  bool get shouldResumeControllerOnAttach =>
      _coordinator.shouldResumeControllerOnAttach(overlayDepth: _overlayDepth);

  void handleAppResumed() {
    if (_disposed || !_isMounted()) {
      return;
    }
    if (!_coordinator.shouldRecoverFromAppResume(overlayDepth: _overlayDepth)) {
      return;
    }
    _overlaySettledTimer?.cancel();
    _overlaySettledTimer = null;
    _overlayDepth = 0;
    _resumeWebView();
    _applyDeferredOverlayRebuild();
  }

  void handleOverlayOpened({
    bool trimKeepAlives = true,
    bool pauseWebView = true,
  }) {
    if (_disposed) {
      return;
    }
    _overlaySettledTimer?.cancel();
    _overlaySettledTimer = null;
    final decision = _coordinator.handleOverlayOpened(
      overlayDepth: _overlayDepth,
    );
    _overlayDepth = decision.overlayDepth;
    if (pauseWebView && decision.shouldPauseWebView) {
      _pauseWebView(trimKeepAlives: trimKeepAlives);
    }
    if (_isMounted()) {
      _rebuild();
    }
  }

  void handleOverlayClosed() {
    if (_disposed) {
      return;
    }
    final decision = _coordinator.handleOverlayClosed(
      overlayDepth: _overlayDepth,
    );
    _overlayDepth = decision.overlayDepth;
    if (decision.shouldResumeWebView) {
      _scheduleOverlaySettledWork(resumeWebView: true);
    }
    if (_isMounted()) {
      _rebuild();
    }
  }

  Future<T> runTrackedOverlay<T>(Future<T> Function() action) async {
    handleOverlayOpened();
    try {
      return await action();
    } finally {
      handleOverlayClosed();
    }
  }

  Future<void> runTrackedOverlayAction(Future<void> Function() action) async {
    await runTrackedOverlay<void>(action);
  }

  void markDeferredOverlayRebuild() {
    if (_disposed) {
      return;
    }
    _hasDeferredOverlayRebuild = true;
  }

  void dispose() {
    _disposed = true;
    _overlaySettledTimer?.cancel();
    _overlaySettledTimer = null;
  }

  void _scheduleOverlaySettledWork({required bool resumeWebView}) {
    if (_disposed) {
      return;
    }
    _overlaySettledTimer?.cancel();
    _overlaySettledTimer = Timer(const Duration(milliseconds: 300), () {
      _overlaySettledTimer = null;
      if (_disposed || !_isMounted() || _overlayDepth > 0) {
        return;
      }
      if (resumeWebView) {
        _resumeWebView();
      }
      _applyDeferredOverlayRebuild();
      if (_isMounted()) {
        _rebuild();
      }
    });
  }

  void _applyDeferredOverlayRebuild() {
    if (!_disposed && _isMounted() && _hasDeferredOverlayRebuild) {
      _hasDeferredOverlayRebuild = false;
      _syncNotifiers();
      _rebuild();
    }
  }
}
