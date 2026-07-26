import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/logging/runtime_logger.dart';
import '../features/proxy/application/proxy_config_mapper.dart';
import '../features/proxy/application/proxy_download_route_resolver.dart';
import '../features/proxy/application/proxy_error_formatter.dart';
import '../features/proxy/application/proxy_latency_tester.dart';
import '../features/proxy/application/proxy_reuse_policy.dart';
import '../features/proxy/application/proxy_runtime_launcher.dart';
import '../features/proxy/application/proxy_webview_target_resolver.dart';
import '../features/proxy/domain/proxy_configuration.dart';
import '../features/proxy/infrastructure/proxy_core_service.dart' as proxy_core;
import '../features/proxy/infrastructure/proxy_latency_probe.dart';

import 'browser_settings.dart';
import 'services/browser_platform_gateway.dart';
import 'services/proxy_webview_bridge.dart';

const String _localProxyHost = '127.0.0.1';

class ProxyService {
  ProxyService._internal({
    required proxy_core.ProxyCoreService proxyCoreService,
    required BrowserPlatformGateway browserPlatformGateway,
  }) : _proxyCoreService = proxyCoreService,
       _browserPlatformGateway = browserPlatformGateway;

  factory ProxyService({
    proxy_core.ProxyCoreService? proxyCoreService,
    MethodChannel? proxyChannel,
    BrowserPlatformGateway? browserPlatformGateway,
    RuntimeLogger? runtimeLogger,
  }) {
    if (proxyCoreService == null &&
        proxyChannel == null &&
        browserPlatformGateway == null) {
      if (runtimeLogger != null) {
        _sharedInstance._proxyCoreService.runtimeLogger = runtimeLogger;
      }
      return _sharedInstance;
    }

    final resolvedChannel =
        proxyChannel ?? const MethodChannel(BrowserPlatformGateway.channelName);
    final resolvedProxyCoreService =
        proxyCoreService ??
        proxy_core.ProxyCoreService(runtimeLogger: runtimeLogger);
    if (runtimeLogger != null) {
      resolvedProxyCoreService.runtimeLogger = runtimeLogger;
    }
    return ProxyService._internal(
      proxyCoreService: resolvedProxyCoreService,
      browserPlatformGateway:
          browserPlatformGateway ??
          BrowserPlatformGateway(channel: resolvedChannel),
    );
  }

  static final ProxyService _sharedInstance = ProxyService._internal(
    proxyCoreService: proxy_core.ProxyCoreService(),
    browserPlatformGateway: BrowserPlatformGateway(),
  );

  final proxy_core.ProxyCoreService _proxyCoreService;
  final BrowserPlatformGateway _browserPlatformGateway;
  final ProxyConfigMapper _configMapper = const ProxyConfigMapper();
  final ProxyDownloadRouteResolver _downloadRouteResolver =
      const ProxyDownloadRouteResolver();
  final ProxyErrorFormatter _errorFormatter = const ProxyErrorFormatter();
  final ProxyLatencyProbe _latencyProbe = const ProxyLatencyProbe();
  final ProxyReusePolicy _reusePolicy = const ProxyReusePolicy();
  late final ProxyRuntimeLauncher _runtimeLauncher = ProxyRuntimeLauncher(
    _configMapper,
  );
  late final ProxyLatencyTester _latencyTester = ProxyLatencyTester(
    latencyProbe: _latencyProbe,
    runtimeLauncher: _runtimeLauncher,
    localProxyHost: _localProxyHost,
  );
  late final ProxyWebViewBridge _webViewBridge = ProxyWebViewBridge(
    _browserPlatformGateway,
  );
  final ProxyWebViewTargetResolver _webViewTargetResolver =
      const ProxyWebViewTargetResolver();

  final _stateController = StreamController<ProxyState>.broadcast();
  ProxyState _currentState = ProxyState.stopped;
  String? _activeProxyFingerprint;

  bool get isRunning => _proxyCoreService.isRunning;

  int? get localProxyPort {
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
    return applyProxyConfiguration(settings.proxyConfiguration);
  }

  Future<void> applyProxyConfiguration(ProxyConfiguration settings) async {
    if (!settings.shouldApplyProxy) {
      await clearProxy();
      return;
    }

    final applyContext = _buildApplyContext(settings);
    if (await _tryReuseExistingProxy(settings, applyContext)) {
      return;
    }

    // Stop any existing local proxy before starting a new one
    await _stopProxyCore();

    if (settings.proxyProtocol == BrowserProxyProtocol.http) {
      await _applyHttpProxy(applyContext);
      return;
    }

    if (_runtimeLauncher.supportsRustProxy(settings.proxyProtocol)) {
      await _applyRustProxy(settings, applyContext);
      return;
    }

    // Unknown protocol - clear proxy
    await clearProxy();
  }

  _ProxyApplyContext _buildApplyContext(ProxyConfiguration settings) {
    final localPort = settings.localProxyPort ?? localProxyPort;
    final target = _resolveWebViewProxyTarget(
      settings,
      localProxyPort: localPort,
    );
    final reuseDecision = _reusePolicy.evaluate(
      settings: settings,
      activeFingerprint: _activeProxyFingerprint,
      proxyCoreIsRunning: _proxyCoreService.isRunning,
      hasResolvedWebViewTarget: target != null,
    );
    return _ProxyApplyContext(
      localPort: localPort,
      target: target,
      reuseDecision: reuseDecision,
    );
  }

  Future<bool> _tryReuseExistingProxy(
    ProxyConfiguration settings,
    _ProxyApplyContext applyContext,
  ) async {
    if (!applyContext.reuseDecision.shouldReuse ||
        applyContext.target == null) {
      return false;
    }

    await _applyWebViewProxyTarget(applyContext.target!);
    _emitState(ProxyState.started);
    return true;
  }

  Future<void> _applyHttpProxy(_ProxyApplyContext applyContext) async {
    if (applyContext.target == null) {
      throw StateError('HTTP proxy target could not be resolved');
    }

    await _applyWebViewProxyTarget(applyContext.target!);
    _activeProxyFingerprint = applyContext.reuseDecision.fingerprint;
    _emitState(ProxyState.started);
  }

  Future<void> _applyRustProxy(
    ProxyConfiguration settings,
    _ProxyApplyContext applyContext,
  ) async {
    _emitState(ProxyState.starting);

    try {
      final listenAddr = '127.0.0.1:${settings.localProxyPort ?? 23333}';
      final result = await _runtimeLauncher.startProxyCore(
        proxyCoreService: _proxyCoreService,
        settings: settings,
        listenAddr: listenAddr,
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

    if (applyContext.localPort == null) {
      await _proxyCoreService.stop();
      _emitState(ProxyState.stopped);
      throw StateError('Local HTTP proxy port was not assigned');
    }

    if (applyContext.target == null) {
      await _proxyCoreService.stop();
      _emitState(ProxyState.stopped);
      throw StateError('Local HTTP proxy target could not be resolved');
    }

    await _applyWebViewProxyTarget(applyContext.target!);
    _activeProxyFingerprint = applyContext.reuseDecision.fingerprint;
    _emitState(ProxyState.started);
  }

  Future<void> clearProxy() async {
    await _stopProxyCore();
    await _clearWebViewProxy();
    _activeProxyFingerprint = null;
    _emitState(ProxyState.stopped);
  }

  ProxyWebViewTarget? _resolveWebViewProxyTarget(
    ProxyConfiguration settings, {
    int? localProxyPort,
  }) {
    return _webViewTargetResolver.resolve(
      settings: settings,
      localProxyHost: _localProxyHost,
      localProxyPort: localProxyPort,
    );
  }

  Future<void> _applyWebViewProxyTarget(ProxyWebViewTarget target) async {
    await _setWebViewProxy(
      target.host,
      target.port,
      scheme: target.scheme,
      bypassDomains: target.bypassDomains,
    );
  }

  Future<void> _stopProxyCore() async {
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
    await _webViewBridge.setProxy(
      host,
      port,
      scheme: scheme,
      bypassDomains: bypassDomains,
    );
  }

  Future<void> _clearWebViewProxy() async {
    await _webViewBridge.clearProxy();
  }

  void _emitState(ProxyState state) {
    _currentState = state;
    _stateController.add(state);
  }

  String describeError(Object error) {
    return _errorFormatter.describe(error);
  }

  String findProxyForDownload(BrowserSettings settings, Uri uri) {
    return findProxyForDownloadConfiguration(settings.proxyConfiguration, uri);
  }

  String findProxyForDownloadConfiguration(
    ProxyConfiguration settings,
    Uri uri,
  ) {
    return _downloadRouteResolver.resolve(
      settings: settings,
      uri: uri,
      localProxyHost: _localProxyHost,
      localProxyPort: settings.localProxyPort ?? localProxyPort,
    );
  }

  Future<Duration?> testNodeLatency(
    BrowserSettings settings, {
    Duration timeout = const Duration(seconds: 10),
    String testUrl = 'https://www.gstatic.com/generate_204',
  }) async {
    return testNodeLatencyConfiguration(
      settings.proxyConfiguration,
      timeout: timeout,
      testUrl: testUrl,
    );
  }

  Future<Duration?> testNodeLatencyConfiguration(
    ProxyConfiguration settings, {
    Duration timeout = const Duration(seconds: 10),
    String testUrl = 'https://www.gstatic.com/generate_204',
  }) async {
    return _latencyTester.testNodeLatency(
      settings: settings,
      proxyCoreService: _proxyCoreService,
      currentLocalProxyPort: localProxyPort,
      timeout: timeout,
      testUrl: testUrl,
    );
  }

  ProxyLatencyTestOperation startNodeLatencyTest(
    BrowserSettings settings, {
    Duration timeout = const Duration(seconds: 10),
    String testUrl = 'https://www.gstatic.com/generate_204',
  }) {
    return startNodeLatencyTestConfiguration(
      settings.proxyConfiguration,
      timeout: timeout,
      testUrl: testUrl,
    );
  }

  ProxyLatencyTestOperation startNodeLatencyTestConfiguration(
    ProxyConfiguration settings, {
    Duration timeout = const Duration(seconds: 10),
    String testUrl = 'https://www.gstatic.com/generate_204',
  }) {
    return _latencyTester.startNodeLatencyTest(
      settings: settings,
      proxyCoreService: _proxyCoreService,
      currentLocalProxyPort: localProxyPort,
      timeout: timeout,
      testUrl: testUrl,
    );
  }

  Future<String> startFloatingButtonMode() async {
    return _browserPlatformGateway.startProxyFloatingButtonMode();
  }

  Future<void> stopFloatingButtonMode() async {
    try {
      await _browserPlatformGateway.stopProxyFloatingButtonMode();
    } catch (_) {}
  }
}

enum ProxyState { starting, started, stopping, stopped }

class _ProxyApplyContext {
  const _ProxyApplyContext({
    required this.localPort,
    required this.target,
    required this.reuseDecision,
  });

  final int? localPort;
  final ProxyWebViewTarget? target;
  final ProxyReuseDecision reuseDecision;
}
