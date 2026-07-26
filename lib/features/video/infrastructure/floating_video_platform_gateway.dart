import 'package:flutter/services.dart';

import '../domain/floating_video_system_ui_runtime.dart';

class FloatingVideoPlatformGateway implements FloatingVideoSystemUiRuntime {
  const FloatingVideoPlatformGateway({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'floating_video';

  final MethodChannel _channel;

  @override
  Future<void> setKeepScreenOn(bool keepOn) async {
    await _channel.invokeMethod<void>('keepScreenOn', <String, Object?>{
      'keepOn': keepOn,
    });
  }
}
