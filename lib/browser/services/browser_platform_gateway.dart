import 'package:flutter/services.dart';

import '../../core/platform/platform_channel_names.dart';

class BrowserPlatformGateway {
  BrowserPlatformGateway({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = PlatformChannelNames.browser;

  final MethodChannel _channel;

  Future<bool> isProxyOverrideSupported() async {
    return await _channel.invokeMethod<bool>(_isSupportedMethod) ?? false;
  }

  Future<bool> setProxy({
    required String host,
    required int port,
    String scheme = 'http',
    List<String> bypassDomains = const [],
  }) async {
    return await _channel.invokeMethod<bool>(_setProxyMethod, <String, Object?>{
          'host': host,
          'port': port,
          'scheme': scheme,
          'bypassDomains': bypassDomains,
        }) ??
        false;
  }

  Future<bool> clearProxy() async {
    return await _channel.invokeMethod<bool>(_clearProxyMethod) ?? false;
  }

  Future<String> startProxyFloatingButtonMode() async {
    return await _channel.invokeMethod<String>(
          _startProxyFloatingButtonModeMethod,
        ) ??
        'unknown';
  }

  Future<bool> stopProxyFloatingButtonMode() async {
    return await _channel.invokeMethod<bool>(
          _stopProxyFloatingButtonModeMethod,
        ) ??
        false;
  }

  static const String _isSupportedMethod = 'isSupported';
  static const String _setProxyMethod = 'setProxy';
  static const String _clearProxyMethod = 'clearProxy';
  static const String _startProxyFloatingButtonModeMethod =
      'startProxyFloatingButtonMode';
  static const String _stopProxyFloatingButtonModeMethod =
      'stopProxyFloatingButtonMode';
}
