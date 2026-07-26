import '../../../core/network/local_proxy_endpoint_provider.dart';
import 'proxy_service.dart';

/// Adapts [ProxyService] to the [LocalProxyEndpointProvider] port.
///
/// Preserves the exact behavior Telegram previously inlined:
/// `proxyService.isRunning ? proxyService.localProxyPort : null`, read fresh on
/// every call. Lives on the proxy/browser side so the port itself stays free of
/// any proxy implementation dependency.
class ProxyServiceLocalEndpointAdapter implements LocalProxyEndpointProvider {
  ProxyServiceLocalEndpointAdapter({ProxyService? proxyService})
    : _proxyService = proxyService ?? ProxyService();

  final ProxyService _proxyService;

  @override
  int? get localSocks5Port =>
      _proxyService.isRunning ? _proxyService.localProxyPort : null;
}
