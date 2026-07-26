import 'proxy_protocol.dart';

class ProxyConfiguration {
  const ProxyConfiguration({
    required this.proxyEnabled,
    required this.proxyHost,
    required this.proxyPort,
    required this.proxyProtocol,
    required this.proxyUuid,
    required this.proxyTlsEnabled,
    required this.proxyTlsInsecure,
    required this.proxyServerName,
    required this.proxyTransportType,
    required this.proxyTransportPath,
    required this.proxyTransportHost,
    required this.proxyPacketEncoding,
    required this.proxyBypassDomainList,
    required this.localProxyPort,
  });

  final bool proxyEnabled;
  final String proxyHost;
  final int? proxyPort;
  final String proxyProtocol;
  final String proxyUuid;
  final bool proxyTlsEnabled;
  final bool proxyTlsInsecure;
  final String proxyServerName;
  final String proxyTransportType;
  final String proxyTransportPath;
  final String proxyTransportHost;
  final String proxyPacketEncoding;
  final List<String> proxyBypassDomainList;
  final int? localProxyPort;

  bool shouldBypassProxyForUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.isEmpty) {
      return true;
    }
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host.startsWith('127.')) {
      return true;
    }
    for (final pattern in proxyBypassDomainList) {
      if (host == pattern || host.endsWith('.$pattern')) {
        return true;
      }
    }
    return false;
  }

  String? get configurationError {
    if (proxyHost.trim().isEmpty) {
      return 'Proxy host is required';
    }

    if (proxyPort == null || proxyPort! <= 0) {
      return 'Proxy port must be a valid number';
    }

    if (localProxyPort != null &&
        (localProxyPort! <= 0 || localProxyPort! > 65535)) {
      return 'Local proxy port must be between 1 and 65535';
    }

    switch (proxyProtocol) {
      case BrowserProxyProtocol.http:
        return null;
      case BrowserProxyProtocol.vless:
        return proxyUuid.trim().isEmpty ? 'VLESS UUID is required' : null;
      case BrowserProxyProtocol.hysteria2:
        return proxyUuid.trim().isEmpty
            ? 'Hysteria2 password is required'
            : null;
    }

    return null;
  }

  String? get validationError {
    if (!proxyEnabled) {
      return null;
    }
    return configurationError;
  }

  bool get hasUsableProxy => configurationError == null;

  bool get shouldApplyProxy => proxyEnabled && hasUsableProxy;
}
