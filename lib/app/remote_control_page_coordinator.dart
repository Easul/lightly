import '../browser/browser_settings_service.dart';
import '../features/easytier/application/easytier_network_info_analyzer.dart';
import '../features/easytier/domain/easytier_runtime.dart';
import '../features/easytier/infrastructure/easytier_service.dart';
import '../features/proxy/domain/proxy_configuration.dart';
import '../features/proxy/domain/proxy_runtime.dart';
import '../features/proxy/infrastructure/proxy_service.dart';
import 'app_runtime_coordinator.dart';

class RemoteControlPageRuntimeState {
  const RemoteControlPageRuntimeState({required this.isProxyRunning});

  final bool isProxyRunning;
}

class RemoteControlPageCoordinator {
  RemoteControlPageCoordinator({
    EasyTierRuntime? easyTier,
    ProxyRuntime? proxy,
    Future<ProxyConfiguration?> Function()? loadProxyConfiguration,
    Future<bool> Function({bool noTunMode})? ensureEasyTier,
    Future<void> Function()? shutdownAll,
  }) : _easyTier = easyTier ?? EasyTierService(),
       _proxy = proxy ?? ProxyService(),
       _loadProxyConfiguration =
           loadProxyConfiguration ?? _loadProductionProxyConfiguration,
       _ensureEasyTier =
           ensureEasyTier ??
           AppRuntimeCoordinator.instance.ensureEasyTierForRemoteControl,
       _shutdownAll = shutdownAll ?? AppRuntimeCoordinator.instance.shutdownAll;

  final EasyTierRuntime _easyTier;
  final ProxyRuntime _proxy;
  final Future<ProxyConfiguration?> Function() _loadProxyConfiguration;
  final Future<bool> Function({bool noTunMode}) _ensureEasyTier;
  final Future<void> Function() _shutdownAll;

  ProxyConfiguration? _proxyConfiguration;

  bool get isEasyTierRunning => _easyTier.isRunning;
  bool get isEasyTierNoTunMode => _easyTier.isNoTunMode;
  int? get activeNoTunSocksPort => _easyTier.activeNoTunSocksPort;
  int? get localProxyPort => _proxy.localProxyPort;
  Stream<bool> get proxyRunningStream => _proxy.runningStream;

  Future<RemoteControlPageRuntimeState> initialize() async {
    _proxyConfiguration = await _loadProxyConfiguration();
    return RemoteControlPageRuntimeState(isProxyRunning: _proxy.isRunning);
  }

  Future<int?> ensureInternalProxyReady({
    required bool useInternalProxy,
  }) async {
    if (!useInternalProxy) {
      return null;
    }

    final configuration = _proxyConfiguration;
    if (configuration == null || !configuration.shouldApplyProxy) {
      throw const RemoteControlPageRuntimeException('请先在设置中配置并启用代理');
    }

    if (!_proxy.isRunning) {
      await _proxy.applyProxy(configuration);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return _proxy.localProxyPort;
  }

  Future<List<Map<String, String>>?> loadReachablePeers() async {
    if (!_easyTier.isRunning) {
      return const <Map<String, String>>[];
    }
    final networkInfo = await _easyTier.getNetworkInfo();
    if (networkInfo == null) {
      return null;
    }
    return EasyTierNetworkInfoAnalyzer.buildPeerSummaries(
      networkInfo,
      _easyTier.currentInstanceName ?? 'ruoqing_vpn',
    ).where((peer) => peer['remoteReachable'] == 'true').toList();
  }

  Future<bool> ensureReceiverNetwork({required bool noTunMode}) {
    return _ensureEasyTier(noTunMode: noTunMode);
  }

  Future<void> shutdownAll() => _shutdownAll();

  static Future<ProxyConfiguration?> _loadProductionProxyConfiguration() async {
    final settings = await BrowserSettingsService().loadSettings();
    return settings.shouldApplyProxy ? settings.proxyConfiguration : null;
  }
}

class RemoteControlPageRuntimeException implements Exception {
  const RemoteControlPageRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}
