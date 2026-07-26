import '../features/remote_control/domain/remote_control_config.dart';
import '../features/remote_control/domain/remote_control_runtime.dart';

class RemoteControlPageReceiverStartException implements Exception {
  const RemoteControlPageReceiverStartException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RemoteControlPageReceiverHelper {
  const RemoteControlPageReceiverHelper();

  Future<RemoteControlPortConfig> startReceiverFlow({
    required RemoteControlPermissionRuntime permissionRuntime,
    required RemoteControlPresentationRuntime service,
    required Future<bool> Function({bool noTunMode}) ensureVpnForRemoteControl,
    required bool useNoTunMode,
  }) async {
    final defaultConfig = await RemoteControlConfig.defaultConfig();
    final config = RemoteControlConfig(
      ports: defaultConfig.ports,
      enableScreen: defaultConfig.enableScreen,
      enableVoice: !useNoTunMode,
      screenFps: defaultConfig.screenFps,
      screenBitrate: defaultConfig.screenBitrate,
    );

    final vpnStarted = await ensureVpnForRemoteControl(noTunMode: useNoTunMode);
    if (!vpnStarted) {
      throw const RemoteControlPageReceiverStartException(
        '请先在设置中配置并选择一个 P2P 网络配置',
      );
    }

    final hasPermission = await permissionRuntime
        .checkAccessibilityPermission();
    if (!hasPermission) {
      await permissionRuntime.openAccessibilitySettings();
      throw const RemoteControlPageReceiverStartException(
        '请在无障碍设置中开启本应用的权限，然后返回重试',
      );
    }

    final ports = await service.startReceiver(config: config);
    final screenCaptureStarted = await service.startScreenCapture(
      fps: config.screenFps,
      bitrate: config.screenBitrate,
    );
    if (!screenCaptureStarted) {
      await service.shutdownReceiverHostResources();
      throw const RemoteControlPageReceiverStartException('请允许屏幕录制后再启动被控端');
    }
    return ports;
  }
}
