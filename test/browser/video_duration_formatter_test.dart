import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/video/presentation/video_duration_formatter.dart';

void main() {
  group('formatVideoDuration', () {
    test('keeps minute-second format below one hour', () {
      expect(
        formatVideoDuration(const Duration(minutes: 29, seconds: 7)),
        '29:07',
      );
    });

    test('includes hours for long videos', () {
      expect(
        formatVideoDuration(const Duration(hours: 1, minutes: 32, seconds: 6)),
        '1:32:06',
      );
    });

    test('does not wrap durations at each hour', () {
      expect(
        formatVideoDuration(const Duration(hours: 12, minutes: 3)),
        '12:03:00',
      );
    });

    test('clamps negative values to zero', () {
      expect(formatVideoDuration(const Duration(seconds: -1)), '00:00');
    });
  });
}
