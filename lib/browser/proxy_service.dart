import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/proxy_core_service.dart' as proxy_core;

import 'browser_settings.dart';
import 'services/proxy_config_mapper.dart';
import 'services/proxy_download_route_resolver.dart';
import 'services/proxy_error_formatter.dart';
import 'services/proxy_latency_probe.dart';
import 'services/proxy_latency_tester.dart';
import 'services/proxy_reuse_policy.dart';
import 'services/proxy_runtime_launcher.dart';
import 'services/proxy_webview_bridge.dart';
import 'services/proxy_webview_target_resolver.dart';

const String _localProxyHost = '127.0.0.1';

class ProxyService {
  ProxyService._internal({
    required proxy_core.ProxyCoreService proxyCoreService,
    required MethodChannel proxyChannel,
  }) : _proxyCoreService = proxyCoreService,
       _proxyChannel = proxyChannel;

  factory ProxyService({
    proxy_core.ProxyCoreService? proxyCoreService,
    MethodChannel? proxyChannel,
  }) {
    if (proxyCoreService == null && proxyChannel == null) {
      return _sharedInstance;
    }

    return ProxyService._internal(
      proxyCoreService: proxyCoreService ?? proxy_core.ProxyCoreService(),
      proxyChannel: proxyChannel ?? const MethodChannel('browser_proxy'),
    );
  }

  static final ProxyService _sharedInstance = ProxyService._internal(
    proxyCoreService: proxy_core.ProxyCoreService(),
    proxyChannel: const MethodChannel('browser_proxy'),
  );

  final proxy_core.ProxyCoreService _proxyCoreService;
  final MethodChannel _proxyChannel;
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
    _proxyChannel,
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

  _ProxyApplyContext _buildApplyContext(BrowserSettings settings) {
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
    BrowserSettings settings,
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
    BrowserSettings settings,
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
    BrowserSettings settings, {
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
    return _latencyTester.testNodeLatency(
      settings: settings,
      proxyCoreService: _proxyCoreService,
      currentLocalProxyPort: localProxyPort,
      timeout: timeout,
      testUrl: testUrl,
    );
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
