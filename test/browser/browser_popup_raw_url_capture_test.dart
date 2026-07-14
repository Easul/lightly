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
  });
}
