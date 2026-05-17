import '../browser_settings.dart';

class ProxyReuseDecision {
  const ProxyReuseDecision({
    required this.fingerprint,
    required this.shouldReuse,
  });

  final String fingerprint;
  final bool shouldReuse;
}

class ProxyReusePolicy {
  const ProxyReusePolicy();

  String buildFingerprint(BrowserSettings settings) {
    return [
      settings.proxyProtocol,
      settings.proxyHost.trim(),
      '${settings.proxyPort ?? ''}',
      settings.proxyUuid.trim(),
      '${settings.proxyTlsEnabled}',
      '${settings.proxyTlsInsecure}',
      settings.proxyServerName.trim(),
      settings.proxyTransportType.trim(),
      settings.proxyTransportPath.trim(),
      settings.proxyTransportHost.trim(),
      settings.proxyPacketEncoding.trim(),
      '${settings.localProxyPort ?? ''}',
      ...settings.proxyBypassDomainList,
    ].join('|');
  }

  ProxyReuseDecision evaluate({
    required BrowserSettings settings,
    required String? activeFingerprint,
    required bool proxyCoreIsRunning,
    required bool hasResolvedWebViewTarget,
  }) {
    final fingerprint = buildFingerprint(settings);
    final sameFingerprint = activeFingerprint == fingerprint;
    final supportsReuse =
        settings.proxyProtocol == BrowserProxyProtocol.http ||
        proxyCoreIsRunning;

    return ProxyReuseDecision(
      fingerprint: fingerprint,
      shouldReuse: sameFingerprint && supportsReuse && hasResolvedWebViewTarget,
    );
  }
}
