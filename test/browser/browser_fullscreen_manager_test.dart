import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_fullscreen_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BrowserFullscreenManager', () {
    late BrowserFullscreenManager manager;

    setUp(() {
      manager = BrowserFullscreenManager();
    });

    test('tracks fullscreen entry and exit state', () async {
      expect(manager.isInWebFullscreen, isFalse);

      await manager.enterWebFullscreen();
      expect(manager.isInWebFullscreen, isTrue);

      await manager.exitWebFullscreen();
      expect(manager.isInWebFullscreen, isFalse);
    });

    test('restorePortraitIfNeeded clears fullscreen state', () async {
      await manager.enterWebFullscreen();

      await manager.restorePortraitIfNeeded();

      expect(manager.isInWebFullscreen, isFalse);
    });
  });
}
