import 'dart:io';

import '../../../core/network/local_proxy_endpoint_provider.dart';
import 'proxy_service.dart';

typedef LocalProxyListenerProbe = Future<bool> Function(String host, int port);

/// Adapts [ProxyService] to the [LocalProxyEndpointProvider] port.
///
/// Preserves the exact behavior Telegram previously inlined:
/// `proxyService.isRunning ? proxyService.localProxyPort : null`, read fresh on
/// every call. Lives on the proxy/browser side so the port itself stays free of
/// any proxy implementation dependency.
class ProxyServiceLocalEndpointAdapter implements LocalProxyEndpointProvider {
  ProxyServiceLocalEndpointAdapter({
    ProxyService? proxyService,
    LocalProxyListenerProbe? listenerProbe,
  }) : _proxyService = proxyService ?? ProxyService(),
       _listenerProbe = listenerProbe ?? _probeListener;

  final ProxyService _proxyService;
  final LocalProxyListenerProbe _listenerProbe;

  @override
  int? get localSocks5Port =>
      _proxyService.isRunning ? _proxyService.localProxyPort : null;

  @override
  Future<int?> resolveAvailableLocalSocks5Port() async {
    final runningPort = localSocks5Port;
    if (runningPort != null) return runningPort;
    final candidatePort = _proxyService.localProxyPort;
    if (candidatePort == null || candidatePort <= 0) return null;
    return await _listenerProbe('127.0.0.1', candidatePort)
        ? candidatePort
        : null;
  }

  static Future<bool> _probeListener(String host, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
