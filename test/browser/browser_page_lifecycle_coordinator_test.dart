import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_lifecycle_coordinator.dart';

void main() {
  group('BrowserPageLifecycleCoordinator', () {
    const coordinator = BrowserPageLifecycleCoordinator();

    test('recovers timers on app resume only when overlays were pending', () {
      expect(coordinator.shouldRecoverFromAppResume(overlayDepth: 0), isFalse);
      expect(coordinator.shouldRecoverFromAppResume(overlayDepth: 2), isTrue);
    });

    test('controller attach resumes only when no overlay is active', () {
      expect(
        coordinator.shouldResumeControllerOnAttach(overlayDepth: 0),
        isTrue,
      );
      expect(
        coordinator.shouldResumeControllerOnAttach(overlayDepth: 1),
        isFalse,
      );
    });

    test('skip rebuild follows overlay visibility', () {
      expect(coordinator.shouldSkipRebuild(overlayDepth: 0), isFalse);
      expect(coordinator.shouldSkipRebuild(overlayDepth: 1), isTrue);
    });

    test('overlay open pauses only on transition from zero to one', () {
      final firstOpen = coordinator.handleOverlayOpened(overlayDepth: 0);
      expect(firstOpen.overlayDepth, 1);
      expect(firstOpen.shouldPauseWebView, isTrue);
      expect(firstOpen.shouldResumeWebView, isFalse);

      final nestedOpen = coordinator.handleOverlayOpened(
        overlayDepth: firstOpen.overlayDepth,
      );
      expect(nestedOpen.overlayDepth, 2);
      expect(nestedOpen.shouldPauseWebView, isFalse);
      expect(nestedOpen.shouldResumeWebView, isFalse);
    });

    test('overlay close resumes only when the last overlay is closed', () {
      final nestedClose = coordinator.handleOverlayClosed(overlayDepth: 2);
      expect(nestedClose.overlayDepth, 1);
      expect(nestedClose.shouldPauseWebView, isFalse);
      expect(nestedClose.shouldResumeWebView, isFalse);

      final finalClose = coordinator.handleOverlayClosed(overlayDepth: 1);
      expect(finalClose.overlayDepth, 0);
      expect(finalClose.shouldPauseWebView, isFalse);
      expect(finalClose.shouldResumeWebView, isTrue);
    });

    test('overlay close clamps depth at zero', () {
      final decision = coordinator.handleOverlayClosed(overlayDepth: 0);
      expect(decision.overlayDepth, 0);
      expect(decision.shouldResumeWebView, isTrue);
    });
  });
}
