import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_force_refresh_coordinator.dart';

void main() {
  group('BrowserForceRefreshCoordinator', () {
    const coordinator = BrowserForceRefreshCoordinator();

    test('stops loading before navigating to controller URL', () async {
      final events = <String>[];

      final refreshedUrl = await coordinator.refresh(
        fallbackUrl: 'https://fallback.example',
        stopLoading: () async => events.add('stop'),
        readCurrentUrl: () async {
          events.add('read');
          return 'https://current.example/page';
        },
        loadUrl: (url) async => events.add('load:$url'),
      );

      expect(refreshedUrl, 'https://current.example/page');
      expect(events, <String>[
        'stop',
        'read',
        'load:https://current.example/page',
      ]);
    });

    test('falls back to tab URL when controller URL cannot be read', () async {
      final loadedUrls = <String>[];

      final refreshedUrl = await coordinator.refresh(
        fallbackUrl: 'https://fallback.example/page',
        stopLoading: () async {},
        readCurrentUrl: () async => throw StateError('renderer unavailable'),
        loadUrl: (url) async => loadedUrls.add(url),
      );

      expect(refreshedUrl, 'https://fallback.example/page');
      expect(loadedUrls, <String>['https://fallback.example/page']);
    });

    test('ignores blank WebView URL and reloads the tab URL', () async {
      final loadedUrls = <String>[];

      final refreshedUrl = await coordinator.refresh(
        fallbackUrl: 'https://fallback.example/page',
        stopLoading: () async {},
        readCurrentUrl: () async => 'about:blank',
        loadUrl: (url) async => loadedUrls.add(url),
      );

      expect(refreshedUrl, 'https://fallback.example/page');
      expect(loadedUrls, <String>['https://fallback.example/page']);
    });

    test('does not navigate when both URLs are empty', () async {
      var loadCount = 0;

      final refreshedUrl = await coordinator.refresh(
        fallbackUrl: ' ',
        stopLoading: () async {},
        readCurrentUrl: () async => null,
        loadUrl: (_) async => loadCount += 1,
      );

      expect(refreshedUrl, isNull);
      expect(loadCount, 0);
    });
  });
}
