import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/utils/browser_popup_filter.dart';

void main() {
  group('BrowserPopupFilter', () {
    test('recognizes supported web schemes', () {
      expect(BrowserPopupFilter.isWebScheme('https'), isTrue);
      expect(BrowserPopupFilter.isWebScheme('FILE'), isTrue);
      expect(BrowserPopupFilter.isWebScheme('content'), isTrue);
      expect(BrowserPopupFilter.isWebScheme('weixin'), isFalse);
    });

    test('suppresses empty blob data and image popup urls', () {
      expect(BrowserPopupFilter.shouldSuppressPopupUrl(null), isTrue);
      expect(
        BrowserPopupFilter.shouldSuppressPopupUrl('blob:https://x'),
        isTrue,
      );
      expect(
        BrowserPopupFilter.shouldSuppressPopupUrl('data:text/plain,1'),
        isTrue,
      );
      expect(
        BrowserPopupFilter.shouldSuppressPopupUrl('https://a.com/image.webp'),
        isTrue,
      );
    });

    test('suppresses linux do avatar urls only', () {
      expect(
        BrowserPopupFilter.shouldSuppressPopupUrl(
          'https://linux.do/user_avatar/foo/bar/120/1.png',
        ),
        isTrue,
      );
      expect(
        BrowserPopupFilter.shouldSuppressPopupUrl('https://example.com/page'),
        isFalse,
      );
    });
  });
}
