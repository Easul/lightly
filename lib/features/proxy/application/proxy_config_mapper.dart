import '../domain/proxy_core_config.dart' as proxy_config;
import '../domain/proxy_configuration.dart';

class ProxyConfigMapper {
  const ProxyConfigMapper();

  proxy_config.VlessConfig buildRustVlessConfig(ProxyConfiguration settings) {
    return proxy_config.VlessConfig(
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

  proxy_config.Hysteria2Config buildRustHysteria2Config(
    ProxyConfiguration settings,
  ) {
    return proxy_config.Hysteria2Config(
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
