import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_tab_session.dart';
import 'package:lightly/pages/browser_page_state_predicates.dart';

void main() {
  group('BrowserPageStatePredicates', () {
    const predicates = BrowserPageStatePredicates();

    test('loads initial url when tab has no retained WebView', () {
      const tab = BrowserTabSession(
        id: 'tab_1',
        url: 'https://example.com',
        hasAttachedWebView: true,
      );

      expect(predicates.shouldLoadInitialUrlForTab(tab), isTrue);
    });

    test('skips initial url only when retained WebView is attached', () {
      final tab = BrowserTabSession(
        id: 'tab_1',
        url: 'https://example.com',
        keepAlive: InAppWebViewKeepAlive(),
        hasAttachedWebView: true,
      );

      expect(predicates.shouldLoadInitialUrlForTab(tab), isFalse);
    });

    test('loads initial url for a fresh tab', () {
      const tab = BrowserTabSession(id: 'tab_1', url: 'https://example.com');

      expect(predicates.shouldLoadInitialUrlForTab(tab), isTrue);
    });
  });
}
