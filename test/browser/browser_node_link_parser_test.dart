import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/services/browser_node_link_parser.dart';

void main() {
  group('BrowserNodeLinkParser', () {
    late BrowserNodeLinkParser parser;

    setUp(() {
      parser = BrowserNodeLinkParser();
    });

    test('parses a valid vless node link into settings', () {
      final result = parser.parseNodeLink(
        'vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?type=ws&path=%2Fws&host=cdn.example.com&security=tls&sni=example.com#Example',
        currentSettings: BrowserSettings.defaults(),
      );

      expect(result.node.name, 'Example');
      expect(result.settings.proxyHost, 'example.com');
      expect(result.settings.proxyPort, 443);
      expect(result.settings.proxyProtocol, BrowserProxyProtocol.vless);
      expect(result.settings.proxyTransportType, 'ws');
      expect(result.settings.proxyTransportPath, '/ws');
      expect(result.settings.proxyTransportHost, 'cdn.example.com');
      expect(result.settings.proxyTlsEnabled, isTrue);
    });

    test('throws clear error for invalid node link', () {
      expect(
        () => parser.parseNodeLink(
          'invalid-link',
          currentSettings: BrowserSettings.defaults(),
        ),
        throwsA(
          isA<BrowserNodeLinkParserException>().having(
            (error) => error.message,
            'message',
            '无法解析该链接，仅支持 vless:// 和 http:// 格式',
          ),
        ),
      );
    });

    test('uses current settings when speed test link is empty', () {
      final currentSettings = BrowserSettings.defaults().copyWith(
        proxyHost: '127.0.0.1',
        proxyPort: 1080,
      );

      final resolved = parser.resolveSettingsForSpeedTest(
        '',
        currentSettings: currentSettings,
      );

      expect(resolved.proxyHost, '127.0.0.1');
      expect(resolved.proxyPort, 1080);
    });
  });
}
