import 'package:flutter/services.dart';

class EasyTierPlatformGateway {
  EasyTierPlatformGateway({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'easytier_vpn';
  static final EasyTierPlatformGateway instance = EasyTierPlatformGateway();

  final MethodChannel _channel;

  Future<bool> parseConfig(String config) async {
    return await _channel.invokeMethod<bool>(
          _parseConfigMethod,
          <String, Object?>{'config': config},
        ) ??
        false;
  }

  Future<bool> checkVpnPermission() async {
    return await _channel.invokeMethod<bool>(_checkVpnPermissionMethod) ??
        false;
  }

  Future<bool> startVpn({
    required String config,
    required String instanceName,
    required bool useAndroidVpn,
  }) async {
    return await _channel.invokeMethod<bool>(_startVpnMethod, <String, Object?>{
          'config': config,
          'instanceName': instanceName,
          'useAndroidVpn': useAndroidVpn,
        }) ??
        false;
  }

  Future<bool> stopVpn() async {
    return await _channel.invokeMethod<bool>(_stopVpnMethod) ?? false;
  }

  Future<String?> getNetworkInfo() {
    return _channel.invokeMethod<String>(_getNetworkInfoMethod);
  }

  Future<String?> getLastError() {
    return _channel.invokeMethod<String>(_getLastErrorMethod);
  }

  static const String _parseConfigMethod = 'parseConfig';
  static const String _checkVpnPermissionMethod = 'checkVpnPermission';
  static const String _startVpnMethod = 'startVpn';
  static const String _stopVpnMethod = 'stopVpn';
  static const String _getNetworkInfoMethod = 'getNetworkInfo';
  static const String _getLastErrorMethod = 'getLastError';
}
