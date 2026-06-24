import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';

void main() {
  group('BrowserSettings', () {
    test('shouldApplyProxy stays false when proxy is disabled', () {
      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: false,
        proxyHost: '127.0.0.1',
        proxyPort: 1080,
      );

      expect(settings.hasUsableProxy, isTrue);
      expect(settings.shouldApplyProxy, isFalse);
      expect(settings.proxyValidationError, isNull);
      expect(settings.homepageUrl, 'https://www.google.com');
      expect(settings.localProxyPort, 23333);
      expect(settings.localHttpRootPath, '/storage/emulated/0/Download');
      expect(
        settings.nativeVideoParserApiBaseUrl,
        'https://parser.example.com',
      );
    });

    test('shouldApplyProxy becomes true for enabled valid proxy', () {
      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyHost: '127.0.0.1',
        proxyPort: 1080,
      );

      expect(settings.hasUsableProxy, isTrue);
      expect(settings.shouldApplyProxy, isTrue);
      expect(settings.homepageUrl, 'https://www.google.com');
      expect(settings.localProxyPort, 23333);
    });

    test('supports HTTP scheme normalization from http://', () {
      final settings = BrowserSettings.fromJson({
        'proxyEnabled': true,
        'proxyHost': 'http.example.com',
        'proxyPort': 1080,
        'proxyScheme': 'http://',
      });

      expect(settings.proxyProtocol, BrowserProxyProtocol.http);
      expect(BrowserProxyProtocol.label(settings.proxyProtocol), 'HTTP');
    });

    test('supports VLESS scheme normalization', () {
      final settings = BrowserSettings.fromJson({
        'proxyEnabled': true,
        'proxyHost': 'vless.example.com',
        'proxyPort': 443,
        'proxyScheme': 'vless',
        'proxyUuid': 'test-uuid',
      });

      expect(settings.proxyProtocol, BrowserProxyProtocol.vless);
      expect(BrowserProxyProtocol.label(settings.proxyProtocol), 'VLESS');
    });

    test('normalizes unknown schemes to http', () {
      final settings = BrowserSettings.fromJson({
        'proxyEnabled': true,
        'proxyHost': 'example.com',
        'proxyPort': 1080,
        'proxyScheme': 'vmess',
      });

      expect(settings.proxyProtocol, BrowserProxyProtocol.http);
    });

    test('VLESS requires UUID', () {
      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyHost: 'example.com',
        proxyPort: 443,
        proxyScheme: BrowserProxyProtocol.vless,
        proxyUuid: '',
      );

      expect(settings.hasUsableProxy, isFalse);
      expect(settings.proxyValidationError, isNotNull);
    });

    test('VLESS with UUID is valid', () {
      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyHost: 'example.com',
        proxyPort: 443,
        proxyScheme: BrowserProxyProtocol.vless,
        proxyUuid: 'my-uuid',
      );

      expect(settings.hasUsableProxy, isTrue);
      expect(settings.proxyValidationError, isNull);
    });

    test('supports Hysteria2 scheme normalization and password validation', () {
      final invalid = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyHost: 'hy2.example.com',
        proxyPort: 443,
        proxyScheme: 'hy2',
        proxyUuid: '',
      );

      expect(invalid.proxyProtocol, BrowserProxyProtocol.hysteria2);
      expect(BrowserProxyProtocol.label(invalid.proxyProtocol), 'Hysteria2');
      expect(invalid.hasUsableProxy, isFalse);

      final valid = invalid.copyWith(proxyUuid: 'secret');
      expect(valid.hasUsableProxy, isTrue);
      expect(valid.proxyValidationError, isNull);
    });

    test('local proxy port must be in valid range', () {
      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyHost: 'example.com',
        proxyPort: 443,
        proxyScheme: BrowserProxyProtocol.vless,
        proxyUuid: 'my-uuid',
        localProxyPort: 70000,
      );

      expect(settings.hasUsableProxy, isFalse);
      expect(settings.proxyValidationError, isNotNull);
    });

    test('same proxy configuration includes local proxy port', () {
      final first = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyHost: 'example.com',
        proxyPort: 443,
        proxyScheme: BrowserProxyProtocol.vless,
        proxyUuid: 'my-uuid',
        localProxyPort: 10808,
      );
      final second = first.copyWith(localProxyPort: 10809);

      expect(first.hasSameProxyConfiguration(second), isFalse);
    });

    test('migrates legacy proxyPassword to proxyUuid', () {
      final settings = BrowserSettings.fromJson({
        'proxyEnabled': true,
        'proxyHost': 'example.com',
        'proxyPort': 1080,
        'proxyScheme': 'http',
        'proxyPassword': 'legacy-pass',
      });

      expect(settings.proxyUuid, 'legacy-pass');
    });

    test('openNewWindowInTab defaults to true', () {
      final settings = BrowserSettings.defaults();

      expect(settings.openNewWindowInTab, isTrue);
      expect(settings.desktopModeEnabled, isFalse);
      expect(settings.desktopUserAgentOverride, isEmpty);
      expect(settings.appCacheAutoClearEnabled, isFalse);
      expect(settings.appCacheAutoClearIntervalHours, 24);
    });

    test('openNewWindowInTab restores from json', () {
      final settings = BrowserSettings.fromJson({
        'homepageUrl': 'https://example.com',
        'openNewWindowInTab': false,
      });

      expect(settings.openNewWindowInTab, isFalse);
    });

    test('desktopModeEnabled restores from json', () {
      final settings = BrowserSettings.fromJson({
        'homepageUrl': 'https://example.com',
        'desktopModeEnabled': true,
      });

      expect(settings.desktopModeEnabled, isTrue);
      expect(settings.toJson()['desktopModeEnabled'], isTrue);
    });

    test('desktopUserAgentOverride restores from json', () {
      final settings = BrowserSettings.fromJson({
        'homepageUrl': 'https://example.com',
        'desktopUserAgentOverride': ' custom ua ',
      });

      expect(settings.desktopUserAgentOverride, ' custom ua ');
      expect(settings.normalizedDesktopUserAgentOverride, 'custom ua');
      expect(settings.toJson()['desktopUserAgentOverride'], ' custom ua ');
    });

    test('app cache auto clear settings restore from json', () {
      final settings = BrowserSettings.fromJson({
        'appCacheAutoClearEnabled': true,
        'appCacheAutoClearIntervalHours': 72,
      });

      expect(settings.appCacheAutoClearEnabled, isTrue);
      expect(settings.appCacheAutoClearIntervalHours, 72);
    });

    test('proxy nodes persist through json', () {
      final settings = BrowserSettings.defaults().copyWith(
        proxyNodes: const <BrowserProxyNode>[
          BrowserProxyNode(
            id: 'node-1',
            name: '主节点',
            proxyHost: 'proxy.example.com',
            proxyPort: 443,
            proxyScheme: BrowserProxyProtocol.vless,
            proxyUuid: 'uuid',
            proxyTlsEnabled: true,
            proxyTlsInsecure: false,
            proxyServerName: 'sni.example.com',
            proxyTransportType: 'ws',
            proxyTransportPath: '/ws',
            proxyTransportHost: 'cdn.example.com',
            proxyPacketEncoding: 'xudp',
          ),
        ],
        selectedProxyNodeId: 'node-1',
      );

      final restored = BrowserSettings.fromJson(settings.toJson());

      expect(restored.selectedProxyNodeId, 'node-1');
      expect(restored.proxyNodes, hasLength(1));
      expect(restored.proxyNodes.single.name, '主节点');
      expect(
        restored.proxyNodes.single.proxyProtocol,
        BrowserProxyProtocol.vless,
      );
      expect(restored.proxyNodes.single.proxyTransportPath, '/ws');
    });

    test(
      'native video parser setting restores from json and trims trailing slash',
      () {
        final settings = BrowserSettings.fromJson({
          'nativeVideoParserApiBaseUrl': 'https://parser.example.com///',
        });

        expect(
          settings.normalizedNativeVideoParserApiBaseUrl,
          'https://parser.example.com',
        );
        expect(settings.canResolveYoutubeWithNativePlayer, isFalse);
        expect(
          settings
              .copyWith(nativeVideoPlayerEnabled: true)
              .canResolveYoutubeWithNativePlayer,
          isTrue,
        );
      },
    );

    test('proxyPacketEncoding restores from json and survives copyWith', () {
      final settings = BrowserSettings.fromJson({
        'proxyScheme': 'vless',
        'proxyPacketEncoding': 'xudp',
      }).copyWith(proxyHost: 'example.com');

      expect(settings.proxyPacketEncoding, 'xudp');
      expect(settings.toJson()['proxyPacketEncoding'], 'xudp');
    });

    test('bypasses proxy for google auth related domains', () {
      final settings = BrowserSettings.defaults();

      expect(
        settings.shouldBypassProxyForUri(
          Uri.parse('https://accounts.google.com'),
        ),
        isTrue,
      );
      expect(
        settings.shouldBypassProxyForUri(Uri.parse('https://apis.google.com')),
        isTrue,
      );
      expect(
        settings.shouldBypassProxyForUri(
          Uri.parse('https://fonts.gstatic.com'),
        ),
        isTrue,
      );
    });

    test('bypasses proxy for hax auth and cloudflare challenge domains', () {
      final settings = BrowserSettings.defaults();

      expect(
        settings.shouldBypassProxyForUri(
          Uri.parse('https://example-site.com/login'),
        ),
        isTrue,
      );
      expect(
        settings.shouldBypassProxyForUri(
          Uri.parse('https://www.example-site.com/account'),
        ),
        isTrue,
      );
      expect(
        settings.shouldBypassProxyForUri(
          Uri.parse(
            'https://challenges.cloudflare.com/cdn-cgi/challenge-platform/h/b/orchestrate/jsch/v1',
          ),
        ),
        isTrue,
      );
    });

    test('built-in bypass domains are included in proxyBypassDomainList', () {
      final settings = BrowserSettings.defaults().copyWith(
        proxyBypassDomains: 'example.com',
      );

      expect(settings.proxyBypassDomainList, contains('example.com'));
      expect(settings.proxyBypassDomainList, contains('google.com'));
      expect(settings.proxyBypassDomainList, contains('example-site.com'));
      expect(
        settings.proxyBypassDomainList,
        contains('challenges.cloudflare.com'),
      );
    });
  });
}
