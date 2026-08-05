import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/video/presentation/video_gesture_math.dart';

void main() {
  group('video gesture math', () {
    test('double tap seeks stay inside the video bounds', () {
      expect(
        offsetVideoPosition(
          position: const Duration(seconds: 2),
          duration: const Duration(minutes: 1),
          offset: const Duration(seconds: -5),
        ),
        Duration.zero,
      );
      expect(
        offsetVideoPosition(
          position: const Duration(seconds: 58),
          duration: const Duration(minutes: 1),
          offset: const Duration(seconds: 5),
        ),
        const Duration(minutes: 1),
      );
    });

    test('horizontal drag uses bounded adaptive sensitivity', () {
      expect(
        horizontalSeekTarget(
          startPosition: const Duration(minutes: 45),
          duration: const Duration(minutes: 90),
          dragDistance: 200,
          surfaceWidth: 400,
        ),
        const Duration(minutes: 49, seconds: 30),
      );
    });

    test('horizontal drag clamps at the start and end', () {
      expect(
        horizontalSeekTarget(
          startPosition: const Duration(seconds: 5),
          duration: const Duration(minutes: 10),
          dragDistance: -400,
          surfaceWidth: 400,
        ),
        Duration.zero,
      );
      expect(
        horizontalSeekTarget(
          startPosition: const Duration(minutes: 9, seconds: 50),
          duration: const Duration(minutes: 10),
          dragDistance: 400,
          surfaceWidth: 400,
        ),
        const Duration(minutes: 10),
      );
    });

    test('double tap splits the surface into three equal zones', () {
      expect(
        classifyVideoDoubleTap(localX: 10, surfaceWidth: 100),
        VideoDoubleTapZone.rewind,
      );
      expect(
        classifyVideoDoubleTap(localX: 30, surfaceWidth: 90),
        VideoDoubleTapZone.rewind,
      );
      expect(
        classifyVideoDoubleTap(localX: 50, surfaceWidth: 100),
        VideoDoubleTapZone.center,
      );
      expect(
        classifyVideoDoubleTap(localX: 60, surfaceWidth: 90),
        VideoDoubleTapZone.forward,
      );
      expect(
        classifyVideoDoubleTap(localX: 90, surfaceWidth: 100),
        VideoDoubleTapZone.forward,
      );
    });
  });
}
