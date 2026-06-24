import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/models/browser_settings_form_data.dart';

void main() {
  group('BrowserSettingsFormData', () {
    test('maps BrowserSettings into form data', () {
      final settings = BrowserSettings.defaults().copyWith(
        homepageUrl: 'https://flutter.dev',
        proxyEnabled: true,
        proxyHost: '127.0.0.1',
        proxyPort: 1080,
        proxyScheme: BrowserProxyProtocol.vless,
        proxyUuid: 'uuid-value',
        proxyTlsEnabled: true,
        proxyTlsInsecure: true,
        proxyServerName: 'server-name',
        proxyTransportType: 'ws',
        proxyTransportPath: '/ws',
        proxyTransportHost: 'example.com',
        proxyPacketEncoding: 'xudp',
        proxyBypassDomains: 'localhost',
        localProxyPort: 23333,
        localHttpServerEnabled: true,
        localHttpRootPath: '/tmp/files',
        localHttpServerPort: 3001,
        localHttpBindAllInterfaces: true,
        localHttpUploadKey: 'upload-key',
        nativeVideoPlayerEnabled: true,
        nativeVideoParserApiBaseUrl: 'https://parser.example.com',
        openNewWindowInTab: false,
        appCacheAutoClearEnabled: true,
        appCacheAutoClearIntervalHours: 72,
      );

      final formData = BrowserSettingsFormData.fromSettings(settings);

      expect(formData.homepageUrl, 'https://flutter.dev');
      expect(formData.proxyHost, '127.0.0.1');
      expect(formData.proxyPortText, '1080');
      expect(formData.localProxyPortText, '23333');
      expect(formData.selectedProtocol, BrowserProxyProtocol.vless);
      expect(formData.proxyTlsEnabled, isTrue);
      expect(formData.proxyNodes, isEmpty);
      expect(formData.selectedProxyNodeId, isNull);
      expect(formData.localHttpPortText, '3001');
      expect(
        formData.nativeVideoParserApiBaseUrl,
        'https://parser.example.com',
      );
      expect(formData.openNewWindowInTab, isFalse);
      expect(formData.appCacheAutoClearEnabled, isTrue);
      expect(formData.appCacheAutoClearIntervalHours, 72);
    });

    test('maps form data back into BrowserSettings', () {
      const formData = BrowserSettingsFormData(
        homepageUrl: 'https://flutter.dev',
        proxyEnabled: true,
        proxyHost: '127.0.0.1',
        proxyPortText: '1080',
        localProxyPortText: '23333',
        proxyUuid: 'uuid-value',
        proxyServerName: 'server-name',
        proxyTransportPath: '/ws',
        proxyTransportHost: 'example.com',
        proxyBypassDomains: 'localhost',
        proxyNodes: <BrowserProxyNode>[],
        selectedProxyNodeId: null,
        localHttpRootPath: '/tmp/files',
        localHttpPortText: '3001',
        localHttpUploadKey: 'upload-key',
        selectedProtocol: BrowserProxyProtocol.vless,
        proxyPacketEncoding: 'xudp',
        selectedTransportType: 'ws',
        proxyTlsEnabled: true,
        proxyTlsInsecure: true,
        localHttpServerEnabled: true,
        localHttpBindAllInterfaces: true,
        nativeVideoPlayerEnabled: true,
        nativeVideoParserApiBaseUrl: 'https://parser.example.com',
        openNewWindowInTab: false,
        appCacheAutoClearEnabled: true,
        appCacheAutoClearIntervalHours: 72,
      );

      final settings = formData.toBrowserSettings();

      expect(settings.homepageUrl, 'https://flutter.dev');
      expect(settings.proxyHost, '127.0.0.1');
      expect(settings.proxyPort, 1080);
      expect(settings.localProxyPort, 23333);
      expect(settings.proxyProtocol, BrowserProxyProtocol.vless);
      expect(settings.proxyTlsEnabled, isTrue);
      expect(settings.localHttpServerPort, 3001);
      expect(
        settings.nativeVideoParserApiBaseUrl,
        'https://parser.example.com',
      );
      expect(settings.openNewWindowInTab, isFalse);
      expect(settings.appCacheAutoClearEnabled, isTrue);
      expect(settings.appCacheAutoClearIntervalHours, 72);
    });
  });
}
