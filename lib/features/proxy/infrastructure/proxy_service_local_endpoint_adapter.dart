import 'dart:io';

import '../../../core/network/local_proxy_endpoint_provider.dart';
import 'proxy_service.dart';

typedef LocalProxyListenerProbe = Future<bool> Function(String host, int port);
typedef PersistedLocalSocks5PortLoader = Future<int?> Function();

/// Adapts [ProxyService] to the [LocalProxyEndpointProvider] port.
///
/// Returns the live runtime port when the Dart owner is healthy. If native state
/// survived a runtime reconstruction, it falls back to the persisted configured
/// port and verifies that endpoint with a SOCKS5 method negotiation.
class ProxyServiceLocalEndpointAdapter implements LocalProxyEndpointProvider {
  ProxyServiceLocalEndpointAdapter({
    ProxyService? proxyService,
    LocalProxyListenerProbe? listenerProbe,
    PersistedLocalSocks5PortLoader? persistedPortLoader,
    bool useRememberedPortFallback = true,
  }) : _proxyService = proxyService ?? ProxyService(),
       _listenerProbe = listenerProbe ?? _probeSocks5Listener,
       _persistedPortLoader = persistedPortLoader ?? _noPersistedPort,
       _useRememberedPortFallback = useRememberedPortFallback;

  final ProxyService _proxyService;
  final LocalProxyListenerProbe _listenerProbe;
  final PersistedLocalSocks5PortLoader _persistedPortLoader;
  final bool _useRememberedPortFallback;

  @override
  int? get localSocks5Port =>
      _proxyService.isRunning ? _proxyService.localProxyPort : null;

  @override
  Stream<void> get changes => _proxyService.runningStream.map<void>((_) {});

  @override
  Future<int?> resolveAvailableLocalSocks5Port() async {
    final runningPort = localSocks5Port;
    if (_isValidPort(runningPort)) return runningPort;
    final persistedPort = await _persistedPortLoader();
    final rememberedPort = _proxyService.localProxyPort;
    final candidates = <int>{
      if (_isValidPort(persistedPort)) persistedPort!,
      if (_useRememberedPortFallback &&
          !_isValidPort(persistedPort) &&
          _isValidPort(rememberedPort))
        rememberedPort!,
    };
    for (final port in candidates) {
      if (await _listenerProbe('127.0.0.1', port)) {
        return port;
      }
    }
    return null;
  }

  static bool _isValidPort(int? port) =>
      port != null && port > 0 && port <= 65535;

  static Future<int?> _noPersistedPort() async => null;

  static Future<bool> _probeSocks5Listener(String host, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      socket.add(const <int>[0x05, 0x01, 0x00]);
      await socket.flush();
      final response = <int>[];
      await for (final chunk in socket.timeout(
        const Duration(milliseconds: 500),
      )) {
        response.addAll(chunk);
        if (response.length >= 2) break;
      }
      return response.length >= 2 && response[0] == 0x05 && response[1] != 0xff;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
