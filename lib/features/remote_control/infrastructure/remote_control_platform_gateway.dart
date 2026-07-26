import 'package:flutter/services.dart';

import '../domain/remote_control_runtime.dart';

class RemoteControlPlatformGateway
    implements RemoteControlPlatformRuntime, RemoteControlPermissionRuntime {
  RemoteControlPlatformGateway({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'remote_control';
  static final RemoteControlPlatformGateway instance =
      RemoteControlPlatformGateway();

  final MethodChannel _channel;

  void setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) {
    _channel.setMethodCallHandler(handler);
  }

  Future<bool?> startReceiver({
    required int controlPort,
    required int screenPort,
    required int screenFps,
    required int screenBitrate,
  }) {
    return _channel.invokeMethod<bool>('startReceiver', <String, Object?>{
      'controlPort': controlPort,
      'screenPort': screenPort,
      'screenFps': screenFps,
      'screenBitrate': screenBitrate,
    });
  }

  Future<bool?> startController(String host) {
    return _channel.invokeMethod<bool>('startController', <String, Object?>{
      'host': host,
    });
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  Future<void> executeCommand(String command) {
    return _channel.invokeMethod<void>('executeCommand', <String, Object?>{
      'command': command,
    });
  }

  Future<bool?> showDisconnectOverlay(String message) {
    return _channel.invokeMethod<bool>(
      'showDisconnectOverlay',
      <String, Object?>{'message': message},
    );
  }

  @override
  Future<bool> checkAccessibilityPermission() async {
    return await _channel.invokeMethod<bool>('checkAccessibilityPermission') ??
        false;
  }

  @override
  Future<void> openAccessibilitySettings() {
    return _channel.invokeMethod<void>('openAccessibilitySettings');
  }

  Future<Map<String, Object?>?> getScreenInfo() async {
    final info = await _channel.invokeMapMethod<Object?, Object?>(
      'getScreenInfo',
    );
    if (info == null) {
      return null;
    }
    return info.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<bool?> startScreenCapture({required int fps, required int bitrate}) {
    return _channel.invokeMethod<bool>('startScreenCapture', <String, Object?>{
      'fps': fps,
      'bitrate': bitrate,
    });
  }

  @override
  Future<void> stopScreenCapture() {
    return _channel.invokeMethod<void>('stopScreenCapture');
  }

  Future<void> requestKeyFrame() {
    return _channel.invokeMethod<void>('requestKeyFrame');
  }

  Future<void> updateBitrate(int bitrate) {
    return _channel.invokeMethod<void>('updateBitrate', <String, Object?>{
      'bitrate': bitrate,
    });
  }

  Future<int?> createScreenTexture({required int width, required int height}) {
    return _channel.invokeMethod<int>('createScreenTexture', <String, Object?>{
      'width': width,
      'height': height,
    });
  }

  Future<void> disposeScreenTexture(int textureId) {
    return _channel.invokeMethod<void>(
      'disposeScreenTexture',
      <String, Object?>{'textureId': textureId},
    );
  }

  Future<void> pushScreenFrame({
    required int textureId,
    required Uint8List data,
    required int type,
    required int timestamp,
  }) {
    return _channel.invokeMethod<void>('pushScreenFrame', <String, Object?>{
      'textureId': textureId,
      'data': data,
      'type': type,
      'timestamp': timestamp,
    });
  }
}
