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

    test('keeps wide viewport for generic sites', () {
      final policy = BrowserWebViewHost.viewportPolicyForUrl(
        'https://example.com',
      );

      expect(policy.usesMobileUserAgent, isTrue);
      expect(policy.useWideViewPort, isTrue);
      expect(policy.loadWithOverviewMode, isTrue);
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

      expect(settings.userAgent, contains('X11; Linux x86_64'));
      expect(settings.useWideViewPort, isTrue);
      expect(settings.loadWithOverviewMode, isTrue);
      expect(settings.preferredContentMode, UserPreferredContentMode.DESKTOP);
    });

    test('settings use mobile content mode when desktop mode is disabled', () {
      final settings = BrowserWebViewHost.settingsForUrl(
        'https://www.youtube.com/watch?v=abc',
      );

      expect(settings.userAgent, contains('Mobile Safari'));
      expect(settings.useWideViewPort, isFalse);
      expect(settings.loadWithOverviewMode, isFalse);
      expect(settings.preferredContentMode, UserPreferredContentMode.MOBILE);
    });
  });
}
