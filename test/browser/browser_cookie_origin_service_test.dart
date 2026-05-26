import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_cookie_origin_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BrowserCookieOriginService', () {
    test('records unique WebView origins and ignores non-web urls', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final service = BrowserCookieOriginService(preferences: preferences);

      await service.recordUrl('https://example.com/path?x=1');
      await service.recordUrl('https://example.com/other');
      await service.recordUrl('http://example.com/plain');
      await service.recordUrl('file:///tmp/local.html');
      await service.recordUrl('about:blank');

      final origins = await service.loadOrigins();

      expect(origins, contains('https://example.com'));
      expect(origins, contains('http://example.com'));
      expect(origins.length, 2);
    });

    test('clears stored origins', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final service = BrowserCookieOriginService(preferences: preferences);

      await service.recordUrl('https://example.com');
      await service.clearOrigins();

      expect(await service.loadOrigins(), isEmpty);
    });
  });
}
