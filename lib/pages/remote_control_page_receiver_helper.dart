import 'package:flutter/services.dart';

import '../models/remote_control_config.dart';
import '../services/remote_control_service.dart';

class RemoteControlPageReceiverStartException implements Exception {
  const RemoteControlPageReceiverStartException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RemoteControlPageReceiverHelper {
  const RemoteControlPageReceiverHelper();

  Future<RemoteControlPortConfig> startReceiverFlow({
    required MethodChannel channel,
    required RemoteControlService service,
    required Future<bool> Function() ensureVpnForRemoteControl,
    required WebRtcIceConfig iceConfig,
  }) async {
    final defaultConfig = await RemoteControlConfig.defaultConfig();
    final config = RemoteControlConfig(
      ports: defaultConfig.ports,
      enableScreen: defaultConfig.enableScreen,
      screenFps: defaultConfig.screenFps,
      screenBitrate: defaultConfig.screenBitrate,
      iceConfig: iceConfig,
    );

    final vpnStarted = await ensureVpnForRemoteControl();
    if (!vpnStarted) {
      throw const RemoteControlPageReceiverStartException(
        '请先在设置中配置并选择一个 P2P 网络配置',
      );
    }

    final hasPermission =
        await channel.invokeMethod<bool>('checkAccessibilityPermission') ??
        false;
    if (!hasPermission) {
      await channel.invokeMethod('openAccessibilitySettings');
      throw const RemoteControlPageReceiverStartException(
        '请在无障碍设置中开启本应用的权限，然后返回重试',
      );
    }

    final ports = await service.startReceiver(config: config);
    await service.startScreenCapture(
      fps: config.screenFps,
      bitrate: config.screenBitrate,
    );
    return ports;
  }
}
