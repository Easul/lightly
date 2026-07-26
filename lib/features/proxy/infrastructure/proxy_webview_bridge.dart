import 'proxy_platform_gateway.dart';

class ProxyWebViewBridge {
  const ProxyWebViewBridge(this._platformGateway);

  final ProxyPlatformGateway _platformGateway;

  Future<void> setProxy(
    String host,
    int port, {
    String scheme = 'http',
    List<String> bypassDomains = const [],
  }) async {
    try {
      await _platformGateway.setProxy(
        host: host,
        port: port,
        scheme: scheme,
        bypassDomains: bypassDomains,
      );
    } catch (_) {
      // Ignore WebView proxy errors on unsupported platforms
    }
  }

  Future<void> clearProxy() async {
    try {
      await _platformGateway.clearProxy();
    } catch (_) {
      // Ignore WebView proxy errors on unsupported platforms
    }
  }
}
