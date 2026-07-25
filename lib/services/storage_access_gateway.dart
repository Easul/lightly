import 'package:flutter/services.dart';

import '../browser/services/browser_platform_gateway.dart';

class StorageAccessGateway {
  StorageAccessGateway({
    MethodChannel channel = const MethodChannel(
      BrowserPlatformGateway.channelName,
    ),
  }) : _channel = channel;

  static final StorageAccessGateway instance = StorageAccessGateway();

  final MethodChannel _channel;

  Future<String?> getSharedDownloadsPath() {
    return _channel.invokeMethod<String>(_getSharedDownloadsPathMethod);
  }

  Future<bool> hasFileAccessPermission() async {
    return await _channel.invokeMethod<bool>(_hasFileAccessPermissionMethod) ??
        false;
  }

  Future<bool> requestFileAccessPermission() async {
    return await _channel.invokeMethod<bool>(
          _requestFileAccessPermissionMethod,
        ) ??
        false;
  }

  static const String _getSharedDownloadsPathMethod = 'getSharedDownloadsPath';
  static const String _hasFileAccessPermissionMethod =
      'hasFileAccessPermission';
  static const String _requestFileAccessPermissionMethod =
      'requestFileAccessPermission';
}
