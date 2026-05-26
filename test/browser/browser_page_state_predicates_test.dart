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

      test('does not reload a tab that already has an attached WebView', () {
        const tab = BrowserTabSession(
          id: 'tab_1',
          url: 'https://example.com/login',
          hasAttachedWebView: true,
        );
        expect(predicates.shouldLoadInitialUrlForTab(tab), isFalse);
      });

      test('loads initial url for restored real-content tab', () {
        const tab = BrowserTabSession(
          id: 'tab_1',
          url: 'https://example.com/page',
          hasAttachedWebView: false,
        );
        expect(predicates.shouldLoadInitialUrlForTab(tab), isTrue);
      });

      test('loads initial url for restored active tab with keepAlive', () {
        final tab = BrowserTabSession(
          id: 'tab_1',
          url: 'https://example.com/page',
          keepAlive: InAppWebViewKeepAlive(),
          hasAttachedWebView: false,
        );
        expect(predicates.shouldLoadInitialUrlForTab(tab), isTrue);
      });
    });

    group('shouldRebuildAfterAddressLoad', () {
      test('rebuilds when loading from favorites page into WebView', () {
        expect(
          predicates.shouldRebuildAfterAddressLoad(wasFavoritesPage: true),
          isTrue,
        );
      });

      test('does not require rebuild when WebView can load directly', () {
        expect(
          predicates.shouldRebuildAfterAddressLoad(wasFavoritesPage: false),
          isFalse,
        );
      });
    });
  });
}
