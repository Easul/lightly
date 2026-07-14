import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/utils/browser_popup_url_decoder.dart';

void main() {
  group('BrowserPopupUrlDecoder', () {
    test('decodes percent-encoded popup url', () {
      expect(
        BrowserPopupUrlDecoder.decodeIfNeeded(
          'baiduboxapp%3A%2F%2Fv1%2Feasy%2Fbydird%3Fupgrade%3D1%26type%3Dhybird',
        ),
        'baiduboxapp://v1/easy/bydird?upgrade=1&type=hybird',
      );
    });

    test('keeps unencoded popup url unchanged', () {
      expect(
        BrowserPopupUrlDecoder.decodeIfNeeded(
          'baiduboxapp://v1/easy/bydird?upgrade=1&type=hybird',
        ),
        'baiduboxapp://v1/easy/bydird?upgrade=1&type=hybird',
      );
    });

    test('keeps malformed percent encoding unchanged', () {
      expect(
        BrowserPopupUrlDecoder.decodeIfNeeded('baiduboxapp%3A%2F%invalid'),
        'baiduboxapp%3A%2F%invalid',
      );
    });

    test('extracts scheme without parsing encoded custom payload', () {
      expect(
        BrowserPopupUrlDecoder.schemeOf(
          'bankabc://{"method":"jumpToSharedProduct"}',
        ),
        'bankabc',
      );
    });

    test('keeps raw encoded url when it already contains a scheme', () {
      const rawUrl = 'bankabc://%7B%22method%22%3A%22jumpToSharedProduct%22%7D';
      expect(
        BrowserPopupUrlDecoder.externalLaunchUrl(
          rawUrl: rawUrl,
          decodedUrl: 'bankabc://{"method":"jumpToSharedProduct"}',
        ),
        rawUrl,
      );
    });

    test('restores known bank payload casing after webview normalization', () {
      const normalizedUrl =
          'bankabc://%7B%22method%22%3A%22jumptosharedproduct%22%2C%22traffictag%22%3A%2290fc%22%7D';

      expect(
        BrowserPopupUrlDecoder.externalLaunchUrl(
          rawUrl: normalizedUrl,
          decodedUrl:
              'bankabc://{"method":"jumptosharedproduct","traffictag":"90fc"}',
        ),
        'bankabc://%7B%22method%22%3A%22jumpToSharedProduct%22%2C%22trafficTag%22%3A%2290fc%22%7D',
      );
    });
  });
}
