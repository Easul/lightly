import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
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

    group('canShowYoutubeScrollPlayButton', () {
      final enabledSettings = BrowserSettings.defaults().copyWith(
        nativeVideoPlayerEnabled: true,
      );
      final parserDisabledSettings = enabledSettings.copyWith(
        nativeVideoParserApiBaseUrl: '',
      );

      test('allows mobile youtube watch pages when parser is enabled', () {
        expect(
          predicates.canShowYoutubeScrollPlayButton(
            url: 'https://m.youtube.com/watch?v=abc123',
            settings: enabledSettings,
          ),
          isTrue,
        );
      });

      test('rejects desktop youtube, non-watch, and disabled parser cases', () {
        expect(
          predicates.canShowYoutubeScrollPlayButton(
            url: 'https://www.youtube.com/watch?v=abc123',
            settings: enabledSettings,
          ),
          isFalse,
        );
        expect(
          predicates.canShowYoutubeScrollPlayButton(
            url: 'https://m.youtube.com/shorts/abc123',
            settings: enabledSettings,
          ),
          isFalse,
        );
        expect(
          predicates.canShowYoutubeScrollPlayButton(
            url: 'https://m.youtube.com/watch?v=abc123',
            settings: parserDisabledSettings,
          ),
          isFalse,
        );
      });
    });

    group('youtube scroll play button visibility', () {
      test(
        'reveals on upward page scroll and hides on downward page scroll',
        () {
          expect(
            predicates.shouldRevealYoutubeScrollPlayButton(
              previousY: 20,
              nextY: 60,
              isEligible: true,
            ),
            isTrue,
          );
          expect(
            predicates.shouldHideYoutubeScrollPlayButton(
              previousY: 60,
              nextY: 20,
              isEligible: true,
            ),
            isTrue,
          );
        },
      );

      test('hides when current page is not eligible', () {
        expect(
          predicates.shouldRevealYoutubeScrollPlayButton(
            previousY: 20,
            nextY: 80,
            isEligible: false,
          ),
          isFalse,
        );
        expect(
          predicates.shouldHideYoutubeScrollPlayButton(
            previousY: 20,
            nextY: 80,
            isEligible: false,
          ),
          isTrue,
        );
      });
    });
  });
}
