import 'package:flutter/services.dart';

import '../../../core/platform/platform_channel_names.dart';
import '../domain/optional_plugin_status.dart';

class OptionalPluginPlatformGateway {
  OptionalPluginPlatformGateway({
    MethodChannel channel = const MethodChannel(
      PlatformChannelNames.optionalPlugins,
    ),
  }) : _channel = channel;

  static final OptionalPluginPlatformGateway instance =
      OptionalPluginPlatformGateway();

  final MethodChannel _channel;

  Future<String?> getSupportedAbi() {
    return _channel.invokeMethod<String>('getSupportedAbi');
  }

  Future<OptionalPluginStatus> getStatus(String packageName) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getPluginStatus',
      <String, Object?>{'packageName': packageName},
    );
    return OptionalPluginStatus.fromMap(
      result ?? const <Object?, Object?>{'installed': false},
    );
  }

  Future<bool> canRequestPackageInstalls() async {
    return await _channel.invokeMethod<bool>('canRequestPackageInstalls') ??
        false;
  }

  Future<void> openInstallPermissionSettings() {
    return _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  Future<OptionalPluginInstallResult> installApk({
    required String path,
    required String expectedPackageName,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'installPluginApk',
      <String, Object?>{
        'path': path,
        'expectedPackageName': expectedPackageName,
      },
    );
    return OptionalPluginInstallResult.fromWireValue(result);
  }

  Future<bool> launchPlugin({
    required String packageName,
    Map<String, Object?> extras = const <String, Object?>{},
  }) async {
    return await _channel.invokeMethod<bool>('launchPlugin', <String, Object?>{
          'packageName': packageName,
          'extras': extras,
        }) ??
        false;
  }
}
