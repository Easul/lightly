import 'package:flutter/services.dart';

class ProxyWebViewBridge {
  const ProxyWebViewBridge(this._proxyChannel);

  final MethodChannel _proxyChannel;

  Future<void> setProxy(
    String host,
    int port, {
    String scheme = 'http',
    List<String> bypassDomains = const [],
  }) async {
    try {
      await _proxyChannel.invokeMethod('setProxy', {
        'host': host,
        'port': port,
        'scheme': scheme,
        'bypassDomains': bypassDomains,
      });
    } catch (_) {
      // Ignore WebView proxy errors on unsupported platforms
    }
  }

  Future<void> clearProxy() async {
    try {
      await _proxyChannel.invokeMethod('clearProxy');
    } catch (_) {
      // Ignore WebView proxy errors on unsupported platforms
    }
  }
}
