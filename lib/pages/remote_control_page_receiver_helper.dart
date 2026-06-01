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
  }) async {
    final config = await RemoteControlConfig.defaultConfig();

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
