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
  });
}
