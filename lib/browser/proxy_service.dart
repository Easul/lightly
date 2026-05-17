import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/proxy_core_service.dart' as proxy_core;

import 'browser_settings.dart';
import 'local_mixed_proxy_server.dart';

class ProxyService {
  ProxyService._internal({
    required LocalMixedProxyServer localProxyServer,
    required proxy_core.ProxyCoreService proxyCoreService,
    required MethodChannel proxyChannel,
  }) : _localProxyServer = localProxyServer,
       _proxyCoreService = proxyCoreService,
       _proxyChannel = proxyChannel;

  factory ProxyService({
    LocalMixedProxyServer? localProxyServer,
    proxy_core.ProxyCoreService? proxyCoreService,
    MethodChannel? proxyChannel,
  }) {
    if (localProxyServer == null &&
        proxyCoreService == null &&
        proxyChannel == null) {
      return _sharedInstance;
    }

    return ProxyService._internal(
      localProxyServer: localProxyServer ?? LocalMixedProxyServer(),
      proxyCoreService: proxyCoreService ?? proxy_core.ProxyCoreService(),
      proxyChannel: proxyChannel ?? const MethodChannel('browser_proxy'),
    );
  }

  static final ProxyService _sharedInstance = ProxyService._internal(
    localProxyServer: LocalMixedProxyServer(),
    proxyCoreService: proxy_core.ProxyCoreService(),
    proxyChannel: const MethodChannel('browser_proxy'),
  );

  final LocalMixedProxyServer _localProxyServer;
  final proxy_core.ProxyCoreService _proxyCoreService;
  final MethodChannel _proxyChannel;

  final _stateController = StreamController<ProxyState>.broadcast();
  ProxyState _currentState = ProxyState.stopped;
  String? _activeProxyFingerprint;

  bool get isRunning =>
      _localProxyServer.isRunning || _proxyCoreService.isRunning;

  int? get localProxyPort {
    if (_localProxyServer.boundPort != null) {
      return _localProxyServer.boundPort;
    }
    final parts = _proxyCoreService.listenAddr.split(':');
    if (parts.length < 2) {
      return null;
    }
    return int.tryParse(parts.last);
  }

  ProxyState get currentState => _currentState;

  Stream<ProxyState> get stateStream => _stateController.stream;

  Future<bool> isSupported() async {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  Future<void> applyProxy(BrowserSettings settings) async {
    if (!settings.shouldApplyProxy) {
      await clearProxy();
      return;
    }

    final fingerprint = _buildProxyFingerprint(settings);
    if (_activeProxyFingerprint == fingerprint) {
      final reattached = await _reattachExistingProxyIfPossible(settings);
      if (reattached) {
        _emitState(ProxyState.started);
        return;
      }
    }

    // Stop any existing local proxy before starting a new one
    await _stopLocalProxy();

    if (settings.proxyProtocol == BrowserProxyProtocol.http) {
      // HTTP: Set WebView proxy directly to the user's HTTP proxy server
      await _setWebViewProxy(
        settings.proxyHost.trim(),
        settings.proxyPort!,
        scheme: 'http',
        bypassDomains: settings.proxyBypassDomainList,
      );
      _activeProxyFingerprint = fingerprint;
      _emitState(ProxyState.started);
      return;
    }

    if (settings.proxyProtocol == BrowserProxyProtocol.vless ||
        settings.proxyProtocol == BrowserProxyProtocol.hysteria2) {
      final isHysteria2 =
          settings.proxyProtocol == BrowserProxyProtocol.hysteria2;

      _emitState(ProxyState.starting);

      try {
        final listenAddr = '127.0.0.1:${settings.localProxyPort ?? 23333}';
        final result = isHysteria2
            ? await _proxyCoreService.startWithHysteria2(
                logLevel: 'debug',
                listenAddr: listenAddr,
                hysteria2Config: _buildRustHysteria2Config(settings),
              )
            : await _proxyCoreService.startWithVless(
                logLevel: 'debug',
                listenAddr: listenAddr,
                vlessConfig: _buildRustVlessConfig(settings),
              );
        if (result != 0) {
          throw StateError(
            '${BrowserProxyProtocol.label(settings.proxyProtocol)} proxy core start failed: $result',
          );
        }
      } catch (e) {
        _emitState(ProxyState.stopped);
        rethrow;
      }

      final localPort = settings.localProxyPort ?? localProxyPort;
      if (localPort == null) {
        await _proxyCoreService.stop();
        _emitState(ProxyState.stopped);
        throw StateError('Local HTTP proxy port was not assigned');
      }

      await _setWebViewProxy(
        LocalMixedProxyServer.localHost,
        localPort,
        scheme: 'http',
        bypassDomains: settings.proxyBypassDomainList,
      );
      _activeProxyFingerprint = fingerprint;
      _emitState(ProxyState.started);
      return;
    }

    // Unknown protocol - clear proxy
    await clearProxy();
  }

  Future<void> clearProxy() async {
    await _stopLocalProxy();
    await _clearWebViewProxy();
    _activeProxyFingerprint = null;
    _emitState(ProxyState.stopped);
  }

  String _buildProxyFingerprint(BrowserSettings settings) {
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

  Future<bool> _reattachExistingProxyIfPossible(
    BrowserSettings settings,
  ) async {
    if (settings.proxyProtocol == BrowserProxyProtocol.http) {
      await _setWebViewProxy(
        settings.proxyHost.trim(),
        settings.proxyPort!,
        scheme: 'http',
        bypassDomains: settings.proxyBypassDomainList,
      );
      return true;
    }

    if (!_localProxyServer.isRunning) {
      if (!_proxyCoreService.isRunning) {
        return false;
      }
    }

    final localPort = settings.localProxyPort ?? this.localProxyPort;
    if (localPort == null) {
      return false;
    }

    await _setWebViewProxy(
      LocalMixedProxyServer.localHost,
      localPort,
      scheme: 'http',
      bypassDomains: settings.proxyBypassDomainList,
    );
    return true;
  }

  Future<void> _stopLocalProxy() async {
    if (_localProxyServer.isRunning) {
      await _localProxyServer.stop();
    }
    if (_proxyCoreService.isRunning) {
      await _proxyCoreService.stop();
    }
  }

  Future<void> _setWebViewProxy(
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

  Future<void> _clearWebViewProxy() async {
    try {
      await _proxyChannel.invokeMethod('clearProxy');
    } catch (_) {
      // Ignore WebView proxy errors on unsupported platforms
    }
  }

  void _emitState(ProxyState state) {
    _currentState = state;
    _stateController.add(state);
  }

  String describeError(Object error) {
    if (error is PlatformException) {
      switch (error.code) {
        case 'UNSUPPORTED':
          return 'WebView proxy override is not supported on this device.';
        case 'INVALID_ARGUMENTS':
          return 'Invalid proxy configuration. Please check host and port.';
        default:
          return error.message ?? 'An unexpected proxy error occurred.';
      }
    }

    if (error is SocketException) {
      return 'Network error: ${error.message}. Please check your connection and server address.';
    }

    if (error is HandshakeException) {
      return 'TLS 握手失败，请检查服务器地址、SNI 和 TLS 设置；如果节点要求，可尝试开启“允许不安全证书”。';
    }

    return 'Failed to update the proxy configuration: $error';
  }

  String findProxyForDownload(BrowserSettings settings, Uri uri) {
    if (!settings.shouldApplyProxy || settings.shouldBypassProxyForUri(uri)) {
      return 'DIRECT';
    }

    if (settings.proxyProtocol == BrowserProxyProtocol.http) {
      return 'PROXY ${settings.proxyHost.trim()}:${settings.proxyPort!}';
    }

    final localPort = settings.localProxyPort ?? this.localProxyPort;
    if (localPort == null) {
      return 'DIRECT';
    }
    return 'PROXY ${LocalMixedProxyServer.localHost}:$localPort';
  }

  Future<Duration?> testNodeLatency(
    BrowserSettings settings, {
    Duration timeout = const Duration(seconds: 10),
    String testUrl = 'https://www.gstatic.com/generate_204',
  }) async {
    final testUri = Uri.parse(testUrl);

    if (!settings.shouldApplyProxy) {
      final httpLatency = await _measureHttpRequest(
        proxy: null,
        timeout: timeout,
        testUrls: [
          testUrl,
          'https://www.google.com/generate_204',
          'https://example.com/',
        ],
      );
      if (httpLatency != null) {
        return httpLatency;
      }
      return _measureTcpConnect(
        host: testUri.host,
        port: testUri.port == 0 ? 443 : testUri.port,
        timeout: timeout,
      );
    }

    if (settings.proxyProtocol == BrowserProxyProtocol.http) {
      final httpLatency = await _measureHttpRequest(
        proxy: 'PROXY ${settings.proxyHost.trim()}:${settings.proxyPort!}',
        timeout: timeout,
        testUrls: [
          testUrl,
          'https://www.google.com/generate_204',
          'https://example.com/',
        ],
      );
      if (httpLatency != null) {
        return httpLatency;
      }
      return _measureTcpConnect(
        host: settings.proxyHost.trim(),
        port: settings.proxyPort!,
        timeout: timeout,
      );
    }

    if (settings.proxyProtocol != BrowserProxyProtocol.vless &&
        settings.proxyProtocol != BrowserProxyProtocol.hysteria2) {
      throw StateError('Unsupported proxy protocol: ${settings.proxyProtocol}');
    }

    final probeTimeout = timeout < const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : timeout;
    final isHysteria2 =
        settings.proxyProtocol == BrowserProxyProtocol.hysteria2;
    final usingExistingRustProxy = _proxyCoreService.isRunning;
    final tempProxyCoreService = usingExistingRustProxy
        ? null
        : proxy_core.ProxyCoreService();
    final tempListenPort = usingExistingRustProxy
        ? localProxyPort
        : await _allocateEphemeralLoopbackPort();

    if (tempListenPort == null) {
      throw StateError('Temporary Rust proxy port was not assigned');
    }

    try {
      if (tempProxyCoreService != null) {
        final listenAddr = '127.0.0.1:$tempListenPort';
        final startResult = isHysteria2
            ? await tempProxyCoreService.startWithHysteria2(
                logLevel: 'debug',
                listenAddr: listenAddr,
                hysteria2Config: _buildRustHysteria2Config(settings),
              )
            : await tempProxyCoreService.startWithVless(
                logLevel: 'debug',
                listenAddr: listenAddr,
                vlessConfig: _buildRustVlessConfig(settings),
              );
        if (startResult != 0) {
          throw StateError('Temporary Rust proxy start failed: $startResult');
        }
      }

      final httpLatency = await _measureHttpRequest(
        proxy: 'PROXY ${LocalMixedProxyServer.localHost}:$tempListenPort',
        timeout: probeTimeout,
        testUrls: [
          testUrl,
          'https://www.google.com/generate_204',
          'https://example.com/',
        ],
      );
      if (httpLatency != null) {
        return httpLatency;
      }
      return _measureTcpConnect(
        host: settings.proxyHost.trim(),
        port: settings.proxyPort!,
        timeout: probeTimeout,
      );
    } finally {
      await tempProxyCoreService?.stop();
    }
  }

  proxy_core.VlessConfig _buildRustVlessConfig(BrowserSettings settings) {
    return proxy_core.VlessConfig(
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

  proxy_core.Hysteria2Config _buildRustHysteria2Config(
    BrowserSettings settings,
  ) {
    return proxy_core.Hysteria2Config(
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

  Future<int?> _allocateEphemeralLoopbackPort() async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      return socket.port;
    } finally {
      await socket?.close();
    }
  }

  Future<Duration?> _measureHttpRequest({
    required String? proxy,
    required Duration timeout,
    required List<String> testUrls,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    if (proxy != null && proxy.isNotEmpty) {
      client.findProxy = (_) => proxy;
    }

    try {
      for (final testUrl in testUrls) {
        final stopwatch = Stopwatch()..start();
        try {
          final request = await client
              .getUrl(Uri.parse(testUrl))
              .timeout(timeout);
          request.followRedirects = true;
          request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
          final response = await request.close().timeout(timeout);
          await response.drain<void>().timeout(timeout);
          stopwatch.stop();
          if (response.statusCode >= 200 && response.statusCode < 500) {
            return stopwatch.elapsed;
          }
        } on TimeoutException {
          continue;
        } on SocketException {
          continue;
        } on HandshakeException {
          continue;
        } on HttpException {
          continue;
        }
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Duration?> _measureTcpConnect({
    required String host,
    required int port,
    required Duration timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      stopwatch.stop();
      return stopwatch.elapsed;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } finally {
      await socket?.close();
    }
  }
}

enum ProxyState { starting, started, stopping, stopped }
