import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/pages/browser_page_settings_helper.dart';

void main() {
  group('BrowserPageSettingsHelper', () {
    const helper = BrowserPageSettingsHelper();
    final settings = BrowserSettings.defaults();

    test('buildInitializedSnapshot marks page initialized', () {
      final snapshot = helper.buildInitializedSnapshot(
        settings: settings,
        proxySupported: true,
        isProxyActive: false,
        statusMessage: 'proxy error',
      );

      expect(snapshot.settings, same(settings));
      expect(snapshot.proxySupported, isTrue);
      expect(snapshot.isProxyActive, isFalse);
      expect(snapshot.statusMessage, 'proxy error');
      expect(snapshot.isInitialized, isTrue);
    });

    test('buildReloadedSnapshot preserves caller initialization state', () {
      final snapshot = helper.buildReloadedSnapshot(
        settings: settings,
        proxySupported: false,
        isProxyActive: true,
        statusMessage: '',
        isInitialized: false,
      );

      expect(snapshot.settings, same(settings));
      expect(snapshot.proxySupported, isFalse);
      expect(snapshot.isProxyActive, isTrue);
      expect(snapshot.statusMessage, isEmpty);
      expect(snapshot.isInitialized, isFalse);
    });
  });
}
