import '../browser/browser_settings.dart';
import '../browser/proxy_service.dart';
import '../models/remote_control_config.dart';
import '../services/remote_control_service.dart';

class RemoteControlPageConnectionException implements Exception {
  const RemoteControlPageConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RemoteControlPageConnectionHelper {
  const RemoteControlPageConnectionHelper();

  Future<int?> ensureInternalProxyReady({
    required bool useInternalProxy,
    required BrowserSettings? settings,
    required ProxyService proxyService,
  }) async {
    if (!useInternalProxy) {
      return null;
    }

    if (settings == null || !settings.shouldApplyProxy) {
      throw const RemoteControlPageConnectionException('请先在设置中配置并启用代理');
    }

    if (!proxyService.isRunning) {
      await proxyService.applyProxy(settings);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    return proxyService.localProxyPort;
  }

  Future<RemoteControlPortConfig?> discoverReceiverPorts({
    required RemoteControlService service,
    required String host,
    required bool useInternalProxy,
    required int? proxyPort,
  }) {
    return service.discoverReceiverPorts(
      host,
      useProxy: useInternalProxy,
      proxyPort: proxyPort,
    );
  }

  String buildConnectErrorMessage(Object? error) {
    return '连接失败: ${error ?? '请检查地址、端口和被控端是否已启动'}';
  }
}
