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

    test('injects desktop environment override for web urls', () {
      final script =
          BrowserSiteCompatibilityScript.desktopViewportOverrideForUrl(
            'https://github.com',
          );

      expect(script, isNotNull);
      expect(script, contains('minimumDesktopWidth = 980'));
      expect(script, contains("'width=' + desktopWidth"));
      expect(script, contains('data-lightly-original-content'));
      expect(script, contains('desktopUserAgentData'));
      expect(script, contains('mobile: false'));
      expect(script, contains('MutationObserver'));
      expect(script, contains('__lightlyApplyDesktopEnvironment'));
      expect(script, isNot(contains('maxTouchPoints')));
      expect(script, isNot(contains('window.matchMedia')));
      expect(script, isNot(contains('window.screen')));
      expect(script, isNot(contains('minWidth')));
    });

    test('desktop environment override uses custom user agent', () {
      final script =
          BrowserSiteCompatibilityScript.desktopViewportOverrideForUrl(
            'https://x.com/home',
            desktopUserAgent: 'Custom "Desktop" UA',
          );

      expect(script, isNotNull);
      expect(script, contains(r'Custom \"Desktop\" UA'));
    });

    test('derives desktop client hints from a custom Linux user agent', () {
      final script =
          BrowserSiteCompatibilityScript.desktopViewportOverrideForUrl(
            'https://duck.ai',
            desktopUserAgent:
                'Mozilla/5.0 (X11; Linux x86_64) Chrome/148.0.0.0',
          );

      expect(script, contains('desktopPlatform = "Linux"'));
      expect(script, contains('desktopNavigatorPlatform = "Linux x86_64"'));
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
