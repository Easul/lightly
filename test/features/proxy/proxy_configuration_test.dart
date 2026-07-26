import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/proxy/domain/proxy_configuration.dart';
import 'package:lightly/features/proxy/domain/proxy_protocol.dart';

void main() {
  ProxyConfiguration configuration({
    bool enabled = true,
    String host = 'proxy.example.com',
    int? port = 443,
    String protocol = BrowserProxyProtocol.vless,
    String credential = 'uuid',
    List<String> bypassDomains = const <String>['google.com'],
    int? localPort = 23333,
  }) {
    return ProxyConfiguration(
      proxyEnabled: enabled,
      proxyHost: host,
      proxyPort: port,
      proxyProtocol: protocol,
      proxyUuid: credential,
      proxyTlsEnabled: true,
      proxyTlsInsecure: false,
      proxyServerName: '',
      proxyTransportType: 'ws',
      proxyTransportPath: '/',
      proxyTransportHost: '',
      proxyPacketEncoding: '',
      proxyBypassDomainList: bypassDomains,
      localProxyPort: localPort,
    );
  }

  test('validates enabled protocol credentials and local port', () {
    expect(configuration().shouldApplyProxy, isTrue);
    expect(configuration(credential: '').shouldApplyProxy, isFalse);
    expect(configuration(localPort: 70000).shouldApplyProxy, isFalse);
    expect(configuration(enabled: false).validationError, isNull);
  });

  test('matches bypass entries only at host boundaries', () {
    final config = configuration();

    expect(
      config.shouldBypassProxyForUri(
        Uri.parse('https://accounts.google.com/login'),
      ),
      isTrue,
    );
    expect(
      config.shouldBypassProxyForUri(
        Uri.parse('https://redirect.googlevideo.com/videoplayback'),
      ),
      isFalse,
    );
  });
}
