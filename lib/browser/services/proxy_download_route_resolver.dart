import '../browser_settings.dart';

class ProxyDownloadRouteResolver {
  const ProxyDownloadRouteResolver();

  String resolve({
    required BrowserSettings settings,
    required Uri uri,
    required String localProxyHost,
    required int? localProxyPort,
  }) {
    if (!settings.shouldApplyProxy || settings.shouldBypassProxyForUri(uri)) {
      return 'DIRECT';
    }

    if (settings.proxyProtocol == BrowserProxyProtocol.http) {
      return 'PROXY ${settings.proxyHost.trim()}:${settings.proxyPort!}';
    }

    if (localProxyPort == null) {
      return 'DIRECT';
    }

    return 'PROXY $localProxyHost:$localProxyPort';
  }
}
