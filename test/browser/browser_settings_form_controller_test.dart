import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/services/browser_settings_form_controller.dart';

void main() {
  group('BrowserSettingsFormController', () {
    late BrowserSettingsFormController controller;

    setUp(() {
      controller = BrowserSettingsFormController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('applies settings and rebuilds them back', () {
      final settings = BrowserSettings.defaults().copyWith(
        homepageUrl: 'https://example.com',
        proxyEnabled: true,
        proxyHost: '1.2.3.4',
        proxyPort: 8080,
        localProxyPort: 9090,
        proxyUuid: 'uuid',
        proxyScheme: BrowserProxyProtocol.vless,
        proxyServerName: 'edge.example.com',
        proxyTransportType: 'ws',
        proxyTransportPath: '/socket',
        proxyTransportHost: 'cdn.example.com',
        proxyPacketEncoding: 'xudp',
        proxyTlsEnabled: true,
        proxyTlsInsecure: true,
        localHttpServerEnabled: true,
        localHttpFavoriteRootPaths: const <String>['/tmp/files', '/tmp/site'],
        localHttpBindAllInterfaces: true,
        nativeVideoPlayerEnabled: true,
        nativeVideoParserApiBaseUrl: 'https://parser.example.com',
        webDebugConsoleEnabled: true,
        desktopUserAgentOverride: ' Desktop UA ',
      );

      controller.applySettings(settings);
      final rebuilt = controller.buildSettings();

      expect(rebuilt.homepageUrl, 'https://example.com');
      expect(rebuilt.proxyEnabled, isTrue);
      expect(rebuilt.proxyHost, '1.2.3.4');
      expect(rebuilt.proxyPort, 8080);
      expect(rebuilt.localProxyPort, 9090);
      expect(rebuilt.proxyProtocol, BrowserProxyProtocol.vless);
      expect(rebuilt.proxyServerName, 'edge.example.com');
      expect(rebuilt.proxyTransportType, 'ws');
      expect(rebuilt.proxyTransportPath, '/socket');
      expect(rebuilt.proxyTransportHost, 'cdn.example.com');
      expect(rebuilt.proxyPacketEncoding, 'xudp');
      expect(rebuilt.proxyTlsEnabled, isTrue);
      expect(rebuilt.proxyTlsInsecure, isTrue);
      expect(rebuilt.localHttpBindAllInterfaces, isTrue);
      expect(rebuilt.localHttpFavoriteRootPaths, <String>[
        '/tmp/files',
        '/tmp/site',
      ]);
      expect(rebuilt.nativeVideoPlayerEnabled, isTrue);
      expect(rebuilt.webDebugConsoleEnabled, isTrue);
      expect(rebuilt.desktopUserAgentOverride, 'Desktop UA');
    });

    test('derived visibility flags follow selected protocol', () {
      controller.selectedProtocol = BrowserProxyProtocol.http;
      expect(controller.showsUuidField, isTrue);
      expect(controller.showsTransportFields, isFalse);
      expect(controller.showsHysteria2ObfsFields, isFalse);
      expect(controller.showsPacketEncodingField, isFalse);
      expect(controller.showsTlsFields, isFalse);

      controller.selectedProtocol = BrowserProxyProtocol.vless;
      expect(controller.showsUuidField, isTrue);
      expect(controller.showsTransportFields, isTrue);
      expect(controller.showsHysteria2ObfsFields, isFalse);
      expect(controller.showsPacketEncodingField, isTrue);
      expect(controller.showsTlsFields, isTrue);

      controller.selectedProtocol = BrowserProxyProtocol.hysteria2;
      expect(controller.showsUuidField, isTrue);
      expect(controller.showsTransportFields, isFalse);
      expect(controller.showsHysteria2ObfsFields, isTrue);
      expect(controller.showsPacketEncodingField, isFalse);
      expect(controller.showsTlsFields, isTrue);
    });

    test('adds and removes normalized local HTTP favorite paths', () {
      expect(controller.addLocalHttpFavoriteRootPath(' /tmp/site/ '), isTrue);
      expect(controller.addLocalHttpFavoriteRootPath('/tmp/site'), isFalse);
      expect(controller.localHttpFavoriteRootPaths, <String>['/tmp/site']);
      expect(controller.removeLocalHttpFavoriteRootPath('/tmp/site'), isTrue);
      expect(controller.localHttpFavoriteRootPaths, isEmpty);
    });
  });
}
