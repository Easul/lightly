import 'package:flutter_test/flutter_test.dart';
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
    });

    test('uses mobile viewport for YouTube', () {
      final policy = BrowserWebViewHost.viewportPolicyForUrl(
        'https://www.youtube.com/watch?v=abc',
      );

      expect(policy.usesMobileUserAgent, isTrue);
      expect(policy.useWideViewPort, isFalse);
      expect(policy.loadWithOverviewMode, isFalse);
    });

    test('keeps wide viewport for generic sites', () {
      final policy = BrowserWebViewHost.viewportPolicyForUrl(
        'https://example.com',
      );

      expect(policy.usesMobileUserAgent, isTrue);
      expect(policy.useWideViewPort, isTrue);
      expect(policy.loadWithOverviewMode, isTrue);
    });
  });
}
