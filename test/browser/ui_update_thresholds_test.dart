import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/utils/ui_update_thresholds.dart';

void main() {
  group('shouldUpdateWebProgress', () {
    test('skips unchanged progress values', () {
      expect(shouldUpdateWebProgress(30, 30), isFalse);
    });

    test('updates for terminal progress values', () {
      expect(shouldUpdateWebProgress(2, 0), isTrue);
      expect(shouldUpdateWebProgress(95, 100), isTrue);
    });

    test('updates only after five point delta', () {
      expect(shouldUpdateWebProgress(10, 14), isFalse);
      expect(shouldUpdateWebProgress(10, 15), isTrue);
      expect(shouldUpdateWebProgress(80, 75), isTrue);
    });
  });

  group('hasSignificantScrollChange', () {
    test('requires at least twenty four pixels of movement', () {
      expect(hasSignificantScrollChange(0, 23.9), isFalse);
      expect(hasSignificantScrollChange(0, 24), isTrue);
      expect(hasSignificantScrollChange(120, 96), isTrue);
    });
  });
}
