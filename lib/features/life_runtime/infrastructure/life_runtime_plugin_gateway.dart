import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/platform/platform_channel_names.dart';

class LifeRuntimePluginGateway {
  LifeRuntimePluginGateway({
    MethodChannel channel = const MethodChannel(
      PlatformChannelNames.lifeRuntimePlugin,
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<String> start(
    String serviceId, {
    String workspace = 'default',
    String host = '127.0.0.1',
    bool allowLan = false,
    int? port,
  }) async {
    final options = <String, Object?>{
      'root': workspace,
      'host': host,
      'allowLan': allowLan,
      ...?(port == null ? null : <String, Object?>{'port': port}),
    };
    return await _channel.invokeMethod<String>('start', <String, Object?>{
          'serviceId': serviceId,
          'optionsJson': jsonEncode(options),
        }) ??
        '{}';
  }

  Future<bool> stop(String serviceId) async {
    return await _channel.invokeMethod<bool>('stop', <String, Object?>{
          'serviceId': serviceId,
        }) ??
        false;
  }

  Future<Map<String, Object?>> status() async {
    final raw = await _channel.invokeMethod<String>('status') ?? '{}';
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
  }

  Future<void> stopAll() => _channel.invokeMethod<void>('stopAll');
}
