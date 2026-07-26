import '../../features/proxy/infrastructure/proxy_core_service.dart'
    as proxy_core;
import '../browser_settings.dart';

class ProxyConfigMapper {
  const ProxyConfigMapper();

  proxy_core.VlessConfig buildRustVlessConfig(BrowserSettings settings) {
    return proxy_core.VlessConfig(
      uuid: settings.proxyUuid.trim(),
      serverAddr: settings.proxyHost.trim(),
      serverPort: settings.proxyPort!,
      security: settings.proxyTlsEnabled ? 'tls' : 'none',
      host: settings.proxyTransportHost.trim().isEmpty
          ? null
          : settings.proxyTransportHost.trim(),
      sni: settings.proxyServerName.trim().isEmpty
          ? null
          : settings.proxyServerName.trim(),
      path: settings.proxyTransportPath.trim().isEmpty
          ? '/'
          : settings.proxyTransportPath.trim(),
      tlsInsecure: settings.proxyTlsInsecure,
    );
  }

  proxy_core.Hysteria2Config buildRustHysteria2Config(
    BrowserSettings settings,
  ) {
    return proxy_core.Hysteria2Config(
      serverAddr: settings.proxyHost.trim(),
      serverPort: settings.proxyPort!,
      password: settings.proxyUuid.trim(),
      sni: settings.proxyServerName.trim().isEmpty
          ? null
          : settings.proxyServerName.trim(),
      obfs: settings.proxyTransportType.trim().isEmpty
          ? null
          : settings.proxyTransportType.trim(),
      obfsPassword: settings.proxyTransportHost.trim().isEmpty
          ? null
          : settings.proxyTransportHost.trim(),
      tlsInsecure: settings.proxyTlsInsecure,
    );
  }
}
