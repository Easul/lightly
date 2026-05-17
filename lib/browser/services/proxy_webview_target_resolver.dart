import '../browser_settings.dart';

class ProxyWebViewTarget {
  const ProxyWebViewTarget({
    required this.host,
    required this.port,
    this.scheme = 'http',
    this.bypassDomains = const [],
  });

  final String host;
  final int port;
  final String scheme;
  final List<String> bypassDomains;
}

class ProxyWebViewTargetResolver {
  const ProxyWebViewTargetResolver();

  ProxyWebViewTarget? resolve({
    required BrowserSettings settings,
    required String localProxyHost,
    required int? localProxyPort,
  }) {
    if (settings.proxyProtocol == BrowserProxyProtocol.http) {
      return ProxyWebViewTarget(
        host: settings.proxyHost.trim(),
        port: settings.proxyPort!,
        bypassDomains: settings.proxyBypassDomainList,
      );
    }

    if (settings.proxyProtocol != BrowserProxyProtocol.vless &&
        settings.proxyProtocol != BrowserProxyProtocol.hysteria2) {
      return null;
    }

    if (localProxyPort == null) {
      return null;
    }

    return ProxyWebViewTarget(
      host: localProxyHost,
      port: localProxyPort,
      bypassDomains: settings.proxyBypassDomainList,
    );
  }
}
