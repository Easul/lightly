import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/platform/platform_channel_names.dart';

class TelegramPluginPlatformGateway {
  TelegramPluginPlatformGateway({
    MethodChannel channel = const MethodChannel(
      PlatformChannelNames.telegramPlugin,
    ),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  static final TelegramPluginPlatformGateway instance =
      TelegramPluginPlatformGateway();

  final MethodChannel _channel;
  final StreamController<String> _results = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<void> _disconnects = StreamController<void>.broadcast(
    sync: true,
  );

  Stream<String> get results => _results.stream;
  Stream<void> get disconnects => _disconnects.stream;

  Future<bool> connect() async {
    return await _channel.invokeMethod<bool>('connect') ?? false;
  }

  Future<int> createClient() async {
    final clientId = await _channel.invokeMethod<int>('createClient');
    if (clientId == null || clientId <= 0) {
      throw StateError('Telegram 插件未能创建 TDLib 客户端');
    }
    return clientId;
  }

  Future<void> send({required int clientId, required String requestJson}) {
    return _channel.invokeMethod<void>('send', <String, Object?>{
      'clientId': clientId,
      'requestJson': requestJson,
    });
  }

  Future<String?> execute(String requestJson) {
    return _channel.invokeMethod<String>('execute', <String, Object?>{
      'requestJson': requestJson,
    });
  }

  Future<void> disconnect() {
    return _channel.invokeMethod<void>('disconnect');
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onResult':
        final result = call.arguments as String?;
        if (result != null && result.isNotEmpty) {
          _results.add(result);
        }
      case 'onDisconnected':
        _disconnects.add(null);
    }
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _results.close();
    await _disconnects.close();
  }
}
