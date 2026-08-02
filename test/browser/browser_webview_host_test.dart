import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:lightly/browser/widgets/browser_webview_host.dart';

void main() {
  group('BrowserWebViewHost viewport policy', () {
    test('uses mobile viewport for x.com', () {
      final policy = BrowserWebViewHost.viewportPolicyForUrl(
        'https://x.com/home',
      );

      expect(policy.usesMobileUserAgent, isTrue);
      expect(policy.useWideViewPort, isFalse);
      expect(policy.loadWithOverviewMode, isFalse);
      expect(policy.preferredContentMode, UserPreferredContentMode.MOBILE);
    });

    test('uses mobile viewport for YouTube', () {
      final policy = BrowserWebViewHost.viewportPolicyForUrl(
        'https://www.youtube.com/watch?v=abc',
      );

      expect(policy.usesMobileUserAgent, isTrue);
      expect(policy.useWideViewPort, isFalse);
      expect(policy.loadWithOverviewMode, isFalse);
      expect(policy.preferredContentMode, UserPreferredContentMode.MOBILE);
    });

    test('uses mobile viewport for generic sites', () {
      final policy = BrowserWebViewHost.viewportPolicyForUrl(
        'https://example.com',
      );

      expect(policy.usesMobileUserAgent, isTrue);
      expect(policy.useWideViewPort, isFalse);
      expect(policy.loadWithOverviewMode, isFalse);
      expect(policy.preferredContentMode, UserPreferredContentMode.MOBILE);
    });

    test('desktop mode overrides mobile site viewport policy', () {
      final policy = BrowserWebViewHost.viewportPolicyForUrl(
        'https://www.youtube.com/watch?v=abc',
        desktopModeEnabled: true,
      );

      expect(policy.usesDesktopUserAgent, isTrue);
      expect(policy.useWideViewPort, isTrue);
      expect(policy.loadWithOverviewMode, isTrue);
      expect(policy.preferredContentMode, UserPreferredContentMode.DESKTOP);
    });

    test('settings use desktop content mode when desktop mode is enabled', () {
      final settings = BrowserWebViewHost.settingsForUrl(
        'https://www.youtube.com/watch?v=abc',
        desktopModeEnabled: true,
      );

      expect(settings.userAgent, contains('Windows NT 10.0; Win64; x64'));
      expect(settings.useWideViewPort, isTrue);
      expect(settings.loadWithOverviewMode, isTrue);
      expect(settings.preferredContentMode, UserPreferredContentMode.DESKTOP);
      expect(settings.initialScale, 100);
      expect(settings.requestedWithHeaderOriginAllowList, isEmpty);
    });

    test('desktop mode fits a 980px layout viewport to a phone width', () {
      final settings = BrowserWebViewHost.settingsForUrl(
        'https://x.com',
        desktopModeEnabled: true,
        webViewLogicalWidth: 406,
        devicePixelRatio: 3,
      );

      expect(settings.initialScale, 124);
      expect(
        BrowserWebViewHost.desktopInitialScaleForWidth(
          904,
          devicePixelRatio: 3,
        ),
        277,
      );
      expect(
        BrowserWebViewHost.desktopInitialScaleForWidth(
          1200,
          devicePixelRatio: 1,
        ),
        122,
      );
    });

    test('desktop mode uses custom user agent override when provided', () {
      final settings = BrowserWebViewHost.settingsForUrl(
        'https://github.com',
        desktopModeEnabled: true,
        desktopUserAgentOverride: ' Custom Desktop UA ',
      );

      expect(settings.userAgent, 'Custom Desktop UA');
      expect(settings.useWideViewPort, isTrue);
      expect(settings.preferredContentMode, UserPreferredContentMode.DESKTOP);
    });

    test('settings use mobile content mode when desktop mode is disabled', () {
      final settings = BrowserWebViewHost.settingsForUrl(
        'https://www.youtube.com/watch?v=abc',
        desktopUserAgentOverride: 'Custom Desktop UA',
      );

      expect(settings.userAgent, contains('Mobile Safari'));
      expect(settings.useWideViewPort, isFalse);
      expect(settings.loadWithOverviewMode, isFalse);
      expect(settings.preferredContentMode, UserPreferredContentMode.MOBILE);
      expect(settings.initialScale, 0);
    });
  });
}
