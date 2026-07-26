import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/video/application/native_video_gesture_controller.dart';

void main() {
  group('NativeVideoGestureController', () {
    test('left side starts brightness gesture and computes hint', () {
      final controller = NativeVideoGestureController();
      controller.startGesture(
        localDx: 10,
        maxWidth: 100,
        brightness: 0.5,
        volume: 0.2,
      );

      final action = controller.updateGesture(
        primaryDelta: -32,
        sensitivity: 320,
      );

      expect(action, isNotNull);
      expect(action!.side, NativeVideoGestureControlSide.brightness);
      expect(action.nextValue, closeTo(0.6, 0.0001));
      expect(action.hint, '亮度 60%');
    });

    test('right side starts volume gesture and can reset', () {
      final controller = NativeVideoGestureController();
      controller.startGesture(
        localDx: 90,
        maxWidth: 100,
        brightness: 0.5,
        volume: 0.2,
      );

      final action = controller.updateGesture(
        primaryDelta: 32,
        sensitivity: 320,
      );

      expect(action, isNotNull);
      expect(action!.side, NativeVideoGestureControlSide.volume);
      expect(action.nextValue, closeTo(0.1, 0.0001));
      expect(action.hint, '音量 10%');

      controller.endGesture();
      expect(
        controller.updateGesture(primaryDelta: 10, sensitivity: 320),
        isNull,
      );
    });

    test('vertical gesture accumulates smooth brightness deltas', () {
      final controller = NativeVideoGestureController();
      controller.startGesture(
        localDx: 10,
        maxWidth: 100,
        brightness: 0.5,
        volume: 0.2,
      );

      final first = controller.updateGesture(
        primaryDelta: -16,
        sensitivity: 320,
      );
      final second = controller.updateGesture(
        primaryDelta: -16,
        sensitivity: 320,
      );

      expect(first?.side, NativeVideoGestureControlSide.brightness);
      expect(first?.nextValue, closeTo(0.55, 0.001));
      expect(second?.nextValue, closeTo(0.60, 0.001));
    });
  });
}
