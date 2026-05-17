import '../../services/proxy_core_service.dart' as proxy_core;
import '../browser_settings.dart';
import 'proxy_config_mapper.dart';

class ProxyRuntimeLauncher {
  const ProxyRuntimeLauncher(this._configMapper);

  final ProxyConfigMapper _configMapper;

  bool supportsRustProxy(String protocol) {
    return protocol == BrowserProxyProtocol.vless ||
        protocol == BrowserProxyProtocol.hysteria2;
  }

  Future<int> startProxyCore({
    required proxy_core.ProxyCoreService proxyCoreService,
    required BrowserSettings settings,
    required String listenAddr,
    String logLevel = 'debug',
  }) {
    if (settings.proxyProtocol == BrowserProxyProtocol.hysteria2) {
      return proxyCoreService.startWithHysteria2(
        logLevel: logLevel,
        listenAddr: listenAddr,
        hysteria2Config: _configMapper.buildRustHysteria2Config(settings),
      );
    }

    if (settings.proxyProtocol == BrowserProxyProtocol.vless) {
      return proxyCoreService.startWithVless(
        logLevel: logLevel,
        listenAddr: listenAddr,
        vlessConfig: _configMapper.buildRustVlessConfig(settings),
      );
    }

    throw StateError(
      'Unsupported Rust proxy protocol: ${settings.proxyProtocol}',
    );
  }
}
