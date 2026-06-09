import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_lifecycle_coordinator.dart';
import 'package:lightly/pages/browser_page_overlay_state_manager.dart';

void main() {
  group('BrowserPageOverlayStateManager', () {
    late _OverlayHarness harness;

    setUp(() {
      harness = _OverlayHarness();
    });

    tearDown(() {
      harness.manager.dispose();
    });

    test('opens first overlay by pausing and rebuilding once', () {
      harness.manager.handleOverlayOpened();

      expect(harness.pauseCount, 1);
      expect(harness.lastTrimKeepAlives, isTrue);
      expect(harness.rebuildCount, 1);
      expect(harness.manager.shouldSkipRebuild, isTrue);
      expect(harness.manager.shouldFreezeWebView, isTrue);
      expect(harness.manager.hasOpenOverlay, isTrue);
      expect(harness.manager.shouldResumeControllerOnAttach, isFalse);
    });

    test('does not pause again for nested overlays', () {
      harness.manager.handleOverlayOpened();
      harness.manager.handleOverlayOpened(trimKeepAlives: false);

      expect(harness.pauseCount, 1);
      expect(harness.rebuildCount, 2);
      expect(harness.manager.shouldSkipRebuild, isTrue);
    });

    test('resumes after final overlay settles', () async {
      harness.manager.handleOverlayOpened();
      harness.manager.handleOverlayClosed();

      expect(harness.resumeCount, 0);
      expect(harness.manager.shouldSkipRebuild, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(harness.resumeCount, 1);
      expect(harness.rebuildCount, 3);
      expect(harness.manager.shouldSkipRebuild, isFalse);
      expect(harness.manager.shouldFreezeWebView, isFalse);
      expect(harness.manager.hasOpenOverlay, isFalse);
      expect(harness.manager.shouldResumeControllerOnAttach, isTrue);
    });

    test('defers rebuild and syncs notifiers after overlay settles', () async {
      harness.manager.handleOverlayOpened();
      harness.manager.markDeferredOverlayRebuild();
      harness.manager.handleOverlayClosed();

      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(harness.syncCount, 1);
      expect(harness.resumeCount, 1);
      expect(harness.rebuildCount, 4);
    });

    test('recovers pending overlay state when app resumes', () {
      harness.manager.handleOverlayOpened();
      harness.manager.markDeferredOverlayRebuild();

      harness.manager.handleAppResumed();

      expect(harness.resumeCount, 1);
      expect(harness.syncCount, 1);
      expect(harness.manager.shouldSkipRebuild, isFalse);
      expect(harness.manager.shouldFreezeWebView, isFalse);
    });

    test('does not resume or rebuild when app resumes after unmount', () {
      harness.manager.handleOverlayOpened();
      harness.manager.markDeferredOverlayRebuild();
      harness.mounted = false;

      harness.manager.handleAppResumed();

      expect(harness.resumeCount, 0);
      expect(harness.syncCount, 0);
      expect(harness.rebuildCount, 1);
    });

    test(
      'does not call callbacks after dispose cancels settle timer',
      () async {
        harness.manager.handleOverlayOpened();
        harness.manager.handleOverlayClosed();
        harness.manager.dispose();

        await Future<void>.delayed(const Duration(milliseconds: 350));

        expect(harness.resumeCount, 0);
        expect(harness.rebuildCount, 2);
      },
    );

    test('ignores late overlay close after dispose', () async {
      harness.manager.handleOverlayOpened();
      harness.manager.dispose();

      harness.manager.handleOverlayClosed();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(harness.resumeCount, 0);
      expect(harness.rebuildCount, 1);
      expect(harness.manager.shouldFreezeWebView, isTrue);
    });
  });
}

class _OverlayHarness {
  _OverlayHarness() {
    manager = BrowserPageOverlayStateManager(
      coordinator: const BrowserPageLifecycleCoordinator(),
      isMounted: () => mounted,
      syncNotifiers: () => syncCount++,
      rebuild: () => rebuildCount++,
      pauseWebView: ({required trimKeepAlives}) {
        pauseCount++;
        lastTrimKeepAlives = trimKeepAlives;
      },
      resumeWebView: () => resumeCount++,
    );
  }

  late final BrowserPageOverlayStateManager manager;
  bool mounted = true;
  int pauseCount = 0;
  int resumeCount = 0;
  int rebuildCount = 0;
  int syncCount = 0;
  bool? lastTrimKeepAlives;
}
