import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_tab_session.dart';
import 'package:lightly/pages/browser_page_state_predicates.dart';

void main() {
  group('BrowserPageStatePredicates', () {
    const predicates = BrowserPageStatePredicates();

    group('shouldLoadInitialUrlForTab', () {
      test('loads initial url for a null tab', () {
        expect(predicates.shouldLoadInitialUrlForTab(null), isTrue);
      });

      test('loads initial url for a fresh tab with empty url', () {
        const tab = BrowserTabSession(id: 'tab_1', url: '');
        expect(predicates.shouldLoadInitialUrlForTab(tab), isTrue);
      });

      test('loads initial url for a tab with about:blank', () {
        const tab = BrowserTabSession(id: 'tab_1', url: 'about:blank');
        expect(predicates.shouldLoadInitialUrlForTab(tab), isTrue);
      });

      test('skips initial url when retained WebView is attached', () {
        final tab = BrowserTabSession(
          id: 'tab_1',
          url: '',
          keepAlive: InAppWebViewKeepAlive(),
          hasAttachedWebView: true,
        );
        expect(predicates.shouldLoadInitialUrlForTab(tab), isFalse);
      });

      test(
        'does not reload a tab that already has real content even without keepAlive',
        () {
          const tab = BrowserTabSession(
            id: 'tab_1',
            url: 'https://agentrouter.org/login',
            hasAttachedWebView: true,
          );
          // Tab has a real URL but keepAlive is null — should NOT reload.
          expect(predicates.shouldLoadInitialUrlForTab(tab), isFalse);
        },
      );

      test(
        'does not reload a tab with real content even when keepAlive was trimmed',
        () {
          const tab = BrowserTabSession(
            id: 'tab_1',
            url: 'https://example.com/page',
            // keepAlive is null (trimmed) and hasAttachedWebView is false
            // (cleared by detachCurrentController during tab switch).
            hasAttachedWebView: false,
          );
          // Still should not reload — the tab already has real content.
          expect(predicates.shouldLoadInitialUrlForTab(tab), isFalse);
        },
      );
    });
  });
}
