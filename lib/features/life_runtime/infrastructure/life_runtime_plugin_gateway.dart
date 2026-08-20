import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/platform/platform_channel_names.dart';
import '../domain/life_runtime_config.dart';

class LifeRuntimePluginGateway {
  LifeRuntimePluginGateway({
    MethodChannel channel = const MethodChannel(
      PlatformChannelNames.lifeRuntimePlugin,
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<String> start(
    String serviceId, {
    String workspace = './',
    String host = '127.0.0.1',
    bool allowLan = false,
    int? port,
    Map<String, Object?> settings = const <String, Object?>{},
  }) async {
    final options = <String, Object?>{
      'root': workspace,
      'host': host,
      'allowLan': allowLan,
      ...settings,
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
    final result = decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
    return result;
  }

  Future<Map<String, Object?>> readConfigFiles() async {
    final raw = await _channel.invokeMethod<String>('readConfigFiles') ?? '{}';
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
  }

  Future<Map<String, Object?>> writeConfigFiles(
    LifeRuntimeConfig config,
  ) async {
    final raw =
        await _channel.invokeMethod<String>(
          'writeConfigFiles',
          <String, Object?>{'configJson': jsonEncode(config.toRuntimeJson())},
        ) ??
        '{}';
    final decoded = jsonDecode(raw);
    final result = decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
    if (result['error'] != null) throw StateError(result['error'].toString());
    return result;
  }

  Future<void> stopAll() => _channel.invokeMethod<void>('stopAll');

  Future<Map<String, Object?>> exportData(LifeRuntimeConfig config) async {
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/life-runtime-export.zip';
    final raw =
        await _channel.invokeMethod<String>('export', <String, Object?>{
          'path': path,
          'configJson': config.encode(),
        }) ??
        '{}';
    final decoded = jsonDecode(raw);
    final result = decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
    result['path'] = path;
    return result;
  }

  Future<Map<String, Object?>> importData(String path) async {
    final raw =
        await _channel.invokeMethod<String>('import', <String, Object?>{
          'path': path,
        }) ??
        '{}';
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
  }
}
