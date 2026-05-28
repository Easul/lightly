import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_address_bar_coordinator.dart';

void main() {
  group('BrowserPageAddressBarCoordinator', () {
    const coordinator = BrowserPageAddressBarCoordinator();

    test('returns empty plan for blank input', () {
      final plan = coordinator.buildLoadPlan(
        rawValue: '   ',
        isProxyActive: false,
        isFavoritesPage: false,
        hasWebViewController: true,
        shouldOpenNativeVideo: false,
      );

      expect(plan.isEmpty, isTrue);
      expect(plan.target, isNull);
    });

    test('loads normalized urls in the current webview', () {
      final plan = coordinator.buildLoadPlan(
        rawValue: 'example.com',
        isProxyActive: false,
        isFavoritesPage: false,
        hasWebViewController: true,
        shouldOpenNativeVideo: false,
      );

      expect(plan.target, 'https://example.com');
      expect(plan.shouldLoadInCurrentWebView, isTrue);
      expect(plan.shouldRebuildAfterAddressLoad, isFalse);
      expect(plan.shouldResetKeepAliveAfterAddressLoad, isFalse);
    });

    test('uses Baidu search when proxy is inactive', () {
      final plan = coordinator.buildLoadPlan(
        rawValue: 'hello world',
        isProxyActive: false,
        isFavoritesPage: false,
        hasWebViewController: true,
        shouldOpenNativeVideo: false,
      );

      expect(plan.target, 'https://www.baidu.com/s?wd=hello%20world');
    });

    test('uses Google search when proxy is active', () {
      final plan = coordinator.buildLoadPlan(
        rawValue: 'hello world',
        isProxyActive: true,
        isFavoritesPage: false,
        hasWebViewController: true,
        shouldOpenNativeVideo: false,
      );

      expect(plan.target, 'https://www.google.com/search?q=hello%20world');
    });

    test('rebuilds instead of loading when leaving favorites page', () {
      final plan = coordinator.buildLoadPlan(
        rawValue: 'https://example.com',
        isProxyActive: false,
        isFavoritesPage: true,
        hasWebViewController: false,
        shouldOpenNativeVideo: false,
      );

      expect(plan.wasFavoritesPage, isTrue);
      expect(plan.shouldLoadInCurrentWebView, isFalse);
      expect(plan.shouldRebuildAfterAddressLoad, isTrue);
      expect(plan.shouldResetKeepAliveAfterAddressLoad, isFalse);
    });

    test('resets keepalive when non-favorites page has no controller', () {
      final plan = coordinator.buildLoadPlan(
        rawValue: 'https://example.com',
        isProxyActive: false,
        isFavoritesPage: false,
        hasWebViewController: false,
        shouldOpenNativeVideo: false,
      );

      expect(plan.shouldLoadInCurrentWebView, isFalse);
      expect(plan.shouldRebuildAfterAddressLoad, isFalse);
      expect(plan.shouldResetKeepAliveAfterAddressLoad, isTrue);
    });

    test('native video plan bypasses webview actions', () {
      final plan = coordinator.buildLoadPlan(
        rawValue: 'https://youtube.com/watch?v=abc',
        isProxyActive: false,
        isFavoritesPage: false,
        hasWebViewController: true,
        shouldOpenNativeVideo: true,
      );

      expect(plan.shouldOpenNativeVideo, isTrue);
      expect(plan.shouldLoadInCurrentWebView, isFalse);
      expect(plan.shouldRebuildAfterAddressLoad, isFalse);
      expect(plan.shouldResetKeepAliveAfterAddressLoad, isFalse);
    });
  });
}
