import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/video/application/browser_video_detection_tracker.dart';

void main() {
  group('BrowserVideoDetectionTracker', () {
    late BrowserVideoDetectionTracker tracker;

    setUp(() {
      tracker = BrowserVideoDetectionTracker();
    });

    test('normalizes youtube watch targets to desktop watch url', () {
      expect(
        tracker.normalizeUrl('https://youtu.be/abc123'),
        'https://www.youtube.com/watch?v=abc123',
      );
    });

    test('skips blob and data urls', () {
      expect(
        tracker.shouldSkipDetectedUrl(
          'blob:https://example.com/1',
          nativeVideoEnabled: true,
        ),
        isTrue,
      );
      expect(
        tracker.shouldSkipDetectedUrl(
          'data:video/mp4;base64,abc',
          nativeVideoEnabled: true,
        ),
        isTrue,
      );
    });

    test('tracks started detection and blocks duplicates', () {
      final normalized = tracker.markDetectionStarted(
        'https://www.youtube.com/watch?v=abc123',
      );

      expect(normalized, 'https://www.youtube.com/watch?v=abc123');
      expect(
        tracker.shouldSkipDetectedUrl(
          'https://youtu.be/abc123',
          nativeVideoEnabled: true,
        ),
        isTrue,
      );
    });

    test('recent dismissal expires after the configured window', () {
      final baseTime = DateTime(2026, 4, 24, 12);
      tracker.rememberDismissedUrl(
        'https://youtu.be/abc123',
        now: () => baseTime,
      );

      expect(
        tracker.wasRecentlyDismissed(
          'https://www.youtube.com/watch?v=abc123',
          now: () => baseTime.add(const Duration(seconds: 11)),
        ),
        isTrue,
      );
      expect(
        tracker.wasRecentlyDismissed(
          'https://www.youtube.com/watch?v=abc123',
          now: () => baseTime.add(const Duration(seconds: 13)),
        ),
        isFalse,
      );
    });
  });
}
