import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/utils/browser_popup_raw_url_capture.dart';

void main() {
  group('BrowserPopupRawUrlCapture', () {
    test('captures window open and raw anchor href values', () {
      expect(BrowserPopupRawUrlCapture.initialScript, contains('window.open'));
      expect(
        BrowserPopupRawUrlCapture.initialScript,
        contains("getAttribute('href')"),
      );
      expect(
        BrowserPopupRawUrlCapture.initialScript,
        contains('__lightlyTakeRawPopupUrl'),
      );
      expect(
        BrowserPopupRawUrlCapture.initialScript,
        contains(BrowserPopupRawUrlCapture.handlerName),
      );
    });

    test('escapes fallback url when building take script', () {
      final script = BrowserPopupRawUrlCapture.takeLatestScript(
        'bankabc://%7B%22method%22%3A%22jumpToSharedProduct%22%7D',
      );

      expect(script, contains('jumpToSharedProduct'));
      expect(script, contains('__lightlyTakeRawPopupUrl'));
    });

    test('accepts only non-empty string capture results', () {
      expect(
        BrowserPopupRawUrlCapture.capturedUrlFromResult('bankabc://raw'),
        'bankabc://raw',
      );
      expect(BrowserPopupRawUrlCapture.capturedUrlFromResult(''), isNull);
      expect(BrowserPopupRawUrlCapture.capturedUrlFromResult(null), isNull);
    });

    test('reads raw url from javascript handler arguments', () {
      expect(
        BrowserPopupRawUrlCapture.capturedUrlFromHandlerArguments([
          'bankabc://raw',
        ]),
        'bankabc://raw',
      );
      expect(
        BrowserPopupRawUrlCapture.capturedUrlFromHandlerArguments([]),
        isNull,
      );
    });

    test('matches captured camel-case url against normalized callback', () {
      final capturedUrls = <String>[
        'bankabc://%7B%22method%22%3A%22jumpToSharedProduct%22%2C%22trafficTag%22%3A%2290fc%22%7D',
      ];

      final captured = BrowserPopupRawUrlCapture.takeBestCapturedUrl(
        capturedUrls,
        'bankabc://%7B%22method%22%3A%22jumptosharedproduct%22%2C%22traffictag%22%3A%2290fc%22%7D',
      );

      expect(captured, contains('jumpToSharedProduct'));
      expect(captured, contains('trafficTag'));
      expect(capturedUrls, isEmpty);
    });
  });
}
