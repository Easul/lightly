import 'package:flutter/foundation.dart';

import '../../features/proxy/domain/proxy_configuration.dart';
import '../../features/proxy/domain/proxy_protocol.dart';
import '../../features/proxy/infrastructure/proxy_core_service.dart'
    as proxy_core;
import 'proxy_config_mapper.dart';

const String _releaseProxyLogLevel = String.fromEnvironment(
  'PROXY_CORE_LOG_LEVEL',
  defaultValue: 'warn',
);

class ProxyRuntimeLauncher {
  const ProxyRuntimeLauncher(this._configMapper);

  final ProxyConfigMapper _configMapper;

  bool supportsRustProxy(String protocol) {
    return protocol == BrowserProxyProtocol.vless ||
        protocol == BrowserProxyProtocol.hysteria2;
  }

  Future<int> startProxyCore({
    required proxy_core.ProxyCoreService proxyCoreService,
    required ProxyConfiguration settings,
    required String listenAddr,
    String logLevel = kReleaseMode ? _releaseProxyLogLevel : 'debug',
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
