class BrowserPageOverlayLifecycleDecision {
  const BrowserPageOverlayLifecycleDecision({
    required this.overlayDepth,
    required this.shouldPauseWebView,
    required this.shouldResumeWebView,
  });

  final int overlayDepth;
  final bool shouldPauseWebView;
  final bool shouldResumeWebView;
}

class BrowserPageLifecycleCoordinator {
  const BrowserPageLifecycleCoordinator();

  bool shouldRecoverFromAppResume({required int overlayDepth}) {
    return overlayDepth > 0;
  }

  bool shouldResumeControllerOnAttach({required int overlayDepth}) {
    return overlayDepth == 0;
  }

  bool shouldSkipRebuild({required int overlayDepth}) {
    return overlayDepth > 0;
  }

  BrowserPageOverlayLifecycleDecision handleOverlayOpened({
    required int overlayDepth,
  }) {
    final nextDepth = overlayDepth + 1;
    return BrowserPageOverlayLifecycleDecision(
      overlayDepth: nextDepth,
      shouldPauseWebView: nextDepth == 1,
      shouldResumeWebView: false,
    );
  }

  BrowserPageOverlayLifecycleDecision handleOverlayClosed({
    required int overlayDepth,
  }) {
    final nextDepth = overlayDepth > 0 ? overlayDepth - 1 : 0;
    return BrowserPageOverlayLifecycleDecision(
      overlayDepth: nextDepth,
      shouldPauseWebView: false,
      shouldResumeWebView: nextDepth == 0,
    );
  }
}
