import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/utils/browser_site_compatibility_script.dart';

void main() {
  group('BrowserSiteCompatibilityScript', () {
    test('injects YouTube bottom navigation fix', () {
      final script = BrowserSiteCompatibilityScript.bottomNavigationFixForUrl(
        'https://m.youtube.com/watch?v=abc',
      );

      expect(script, isNotNull);
      expect(script, contains('lightly-youtube-bottom-nav-fix'));
      expect(script, contains('ytm-pivot-bar-renderer'));
    });

    test('injects X bottom navigation fix', () {
      final script = BrowserSiteCompatibilityScript.bottomNavigationFixForUrl(
        'https://x.com/home',
      );

      expect(script, isNotNull);
      expect(script, contains('lightly-x-bottom-nav-fix'));
      expect(script, contains('BottomBar'));
    });

    test('does not inject for generic sites', () {
      final script = BrowserSiteCompatibilityScript.bottomNavigationFixForUrl(
        'https://example.com',
      );

      expect(script, isNull);
    });

    test('injects desktop viewport override for web urls', () {
      final script =
          BrowserSiteCompatibilityScript.desktopViewportOverrideForUrl(
            'https://github.com',
          );

      expect(script, isNotNull);
      expect(script, contains('width=1280'));
      expect(script, contains('data-lightly-original-content'));
    });

    test('does not inject desktop viewport override for local files', () {
      final script =
          BrowserSiteCompatibilityScript.desktopViewportOverrideForUrl(
            'file:///storage/emulated/0/index.html',
          );

      expect(script, isNull);
    });
  });
}
