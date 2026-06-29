import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/browser_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BrowserSettingsService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('loadSettings returns defaults when nothing is stored', () async {
      final service = BrowserSettingsService();

      final settings = await service.loadSettings();

      expect(settings.homepageUrl, 'https://www.google.com');
      expect(settings.proxyEnabled, isFalse);
      expect(settings.proxyHost, '');
      expect(settings.proxyPort, isNull);
      expect(settings.localProxyPort, 23333);
      expect(settings.proxyScheme, BrowserProxyProtocol.http);
      expect(settings.nativeVideoPlayerEnabled, isFalse);
      expect(settings.localHttpServerEnabled, isFalse);
      expect(settings.localHttpRootPath, '/storage/emulated/0/Download');
      expect(
        settings.nativeVideoParserApiBaseUrl,
        'https://parser.example.com',
      );
      expect(settings.openNewWindowInTab, isTrue);
      expect(settings.webDebugConsoleEnabled, isFalse);
    });

    test('saveSettings persists values', () async {
      final service = BrowserSettingsService();
      final settings = BrowserSettings.defaults().copyWith(
        homepageUrl: 'https://flutter.dev',
        proxyEnabled: true,
        proxyHost: '127.0.0.1',
        proxyPort: 1080,
        localProxyPort: 10808,
        proxyScheme: BrowserProxyProtocol.http,
        nativeVideoPlayerEnabled: true,
        nativeVideoParserApiBaseUrl: 'https://parser.custom.example',
        openNewWindowInTab: false,
        webDebugConsoleEnabled: true,
      );

      await service.saveSettings(settings);
      final restored = await service.loadSettings();

      expect(restored.homepageUrl, 'https://flutter.dev');
      expect(restored.proxyEnabled, isTrue);
      expect(restored.proxyHost, '127.0.0.1');
      expect(restored.proxyPort, 1080);
      expect(restored.localProxyPort, 10808);
      expect(restored.proxyScheme, BrowserProxyProtocol.http);
      expect(restored.nativeVideoPlayerEnabled, isTrue);
      expect(
        restored.nativeVideoParserApiBaseUrl,
        'https://parser.custom.example',
      );
      expect(restored.openNewWindowInTab, isFalse);
      expect(restored.webDebugConsoleEnabled, isTrue);
    });
  });
}
