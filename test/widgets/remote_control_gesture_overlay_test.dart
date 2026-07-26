import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/presentation/widgets/remote_control_gesture_overlay.dart';

void main() {
  testWidgets('annotation mode emits a circle instead of a gesture', (
    tester,
  ) async {
    var gestureCount = 0;
    double? emittedCenterX;
    double? emittedCenterY;
    double? emittedRadius;

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 200,
            child: RemoteControlGestureOverlay(
              displayScreenSize: const Size(200, 200),
              targetScreenSize: const Size(400, 400),
              useAnnotationMode: true,
              onGesture: (_) => gestureCount++,
              onAnnotationCircle:
                  ({
                    required double centerX,
                    required double centerY,
                    required double radius,
                  }) {
                    emittedCenterX = centerX;
                    emittedCenterY = centerY;
                    emittedRadius = radius;
                  },
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(20, 20));
    await gesture.moveTo(const Offset(180, 20));
    await tester.pump();
    await gesture.moveTo(const Offset(180, 180));
    await tester.pump();
    await gesture.up();

    expect(gestureCount, 0);
    expect(emittedCenterX, 200);
    expect(emittedCenterY, 200);
    expect(emittedRadius, 160);
  });

  testWidgets('annotation mode emits closed circles near the start point', (
    tester,
  ) async {
    double? emittedRadius;

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 200,
            child: RemoteControlGestureOverlay(
              displayScreenSize: const Size(200, 200),
              targetScreenSize: const Size(400, 400),
              useAnnotationMode: true,
              onAnnotationCircle:
                  ({
                    required double centerX,
                    required double centerY,
                    required double radius,
                  }) {
                    emittedRadius = radius;
                  },
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(100, 20));
    await gesture.moveTo(const Offset(180, 100));
    await tester.pump();
    await gesture.moveTo(const Offset(100, 180));
    await tester.pump();
    await gesture.moveTo(const Offset(20, 100));
    await tester.pump();
    await gesture.moveTo(const Offset(104, 23));
    await tester.pump();
    await gesture.up();

    expect(emittedRadius, 160);
  });

  test('swipe trail paint uses stroke mode instead of polygon fill', () {
    final paint = createSwipeTrailPaint();

    expect(paint.style, PaintingStyle.stroke);
    expect(paint.strokeCap, StrokeCap.round);
    expect(paint.strokeJoin, StrokeJoin.round);
  });

  test('annotation trail paint uses stroke mode', () {
    final paint = createAnnotationTrailPaint();

    expect(paint.style, PaintingStyle.stroke);
    expect(paint.strokeCap, StrokeCap.round);
    expect(paint.strokeJoin, StrokeJoin.round);
  });
}
