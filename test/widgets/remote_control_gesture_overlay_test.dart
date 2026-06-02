import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/widgets/remote_control_gesture_overlay.dart';

void main() {
  test('swipe trail paint uses stroke mode instead of polygon fill', () {
    final paint = createSwipeTrailPaint();

    expect(paint.style, PaintingStyle.stroke);
    expect(paint.strokeCap, StrokeCap.round);
    expect(paint.strokeJoin, StrokeJoin.round);
  });
}
