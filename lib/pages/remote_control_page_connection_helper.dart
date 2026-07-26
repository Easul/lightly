import '../features/remote_control/domain/remote_control_config.dart';
import '../services/remote_control_service.dart';

class RemoteControlPageConnectionHelper {
  const RemoteControlPageConnectionHelper();

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
