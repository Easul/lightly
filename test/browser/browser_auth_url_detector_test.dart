import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/utils/browser_auth_url_detector.dart';

void main() {
  group('BrowserAuthUrlDetector', () {
    test('detects trusted auth popup hosts', () {
      expect(
        BrowserAuthUrlDetector.isTrustedAuthPopupUrl(
          'https://accounts.google.com/signin/v2/identifier',
        ),
        isTrue,
      );
      expect(
        BrowserAuthUrlDetector.isTrustedAuthPopupUrl(
          'https://oauth.telegram.org/auth?bot_id=1',
        ),
        isTrue,
      );
    });

    test('detects auth-like urls by path and query', () {
      expect(
        BrowserAuthUrlDetector.looksLikeAuthUrl(
          'https://example.com/login?next=/home',
        ),
        isTrue,
      );
      expect(
        BrowserAuthUrlDetector.looksLikeAuthUrl(
          'https://example.com/path?mode=telegram',
        ),
        isTrue,
      );
      expect(
        BrowserAuthUrlDetector.looksLikeAuthUrl('https://example.com/video'),
        isFalse,
      );
    });
  });
}
