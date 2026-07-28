/// Cross-feature port for reading the app's local SOCKS5 proxy endpoint.
///
/// This exists so features that only need "the local proxy port, if any"
/// (e.g. Telegram/TDLib) do not import a concrete proxy implementation and do
/// not create a `feature → feature` dependency. The proxy feature provides an
/// adapter implementing this port; the composition root injects it.
///
/// Contract: [localSocks5Port] returns the port the local mixed HTTP/SOCKS5
/// proxy is currently listening on, or `null` when the proxy is not running.
/// It must be cheap to call repeatedly and reflect the live runtime state at
/// call time (callers poll it before each use).
abstract class LocalProxyEndpointProvider {
  int? get localSocks5Port;

  Future<int?> resolveAvailableLocalSocks5Port() async => localSocks5Port;
}
