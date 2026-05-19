import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_video_detection_coordinator.dart';
import 'package:lightly/browser/services/browser_video_detection_tracker.dart';

void main() {
  group('BrowserVideoDetectionCoordinator', () {
    late BrowserVideoDetectionTracker tracker;
    late BrowserVideoDetectionCoordinator coordinator;

    setUp(() {
      tracker = BrowserVideoDetectionTracker();
      coordinator = BrowserVideoDetectionCoordinator(tracker: tracker);
    });

    test('disables repeated script injection by default', () {
      expect(coordinator.shouldInjectScript(nativeVideoEnabled: true), isFalse);

      coordinator.markScriptInjected();
      expect(coordinator.shouldInjectScript(nativeVideoEnabled: true), isFalse);

      coordinator.resetAll();
      expect(coordinator.shouldInjectScript(nativeVideoEnabled: true), isFalse);
    });

    test(
      'handleDetectedVideo normalizes and clears processing later',
      () async {
        String? openedUrl;

        await coordinator.handleDetectedVideo(
          'https://m.youtube.com/watch?v=abc123',
          nativeVideoEnabled: true,
          onOpenVideo: (url) async {
            openedUrl = url;
          },
        );

        expect(openedUrl, 'https://www.youtube.com/watch?v=abc123');
        expect(tracker.isProcessing, isTrue);

        await Future<void>.delayed(const Duration(seconds: 3));
        expect(tracker.isProcessing, isFalse);
      },
    );

    test('buildInjectionScript preserves mutation observer scheduling', () {
      final script = coordinator.buildInjectionScript();

      expect(script, contains('MutationObserver'));
      expect(script, contains('scheduleReport'));
      expect(script, contains('setTimeout(function()'));
    });
  });
}
