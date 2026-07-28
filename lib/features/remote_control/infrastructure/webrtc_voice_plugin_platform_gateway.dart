import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/platform/platform_channel_names.dart';

typedef WebRtcPluginJson = Map<String, dynamic>;

class WebRtcVoicePluginPlatformGateway {
  WebRtcVoicePluginPlatformGateway({
    MethodChannel channel = const MethodChannel(
      PlatformChannelNames.webRtcVoicePlugin,
    ),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  static final WebRtcVoicePluginPlatformGateway instance =
      WebRtcVoicePluginPlatformGateway();

  final MethodChannel _channel;
  final StreamController<WebRtcPluginJson> _events =
      StreamController<WebRtcPluginJson>.broadcast(sync: true);
  final StreamController<void> _disconnects = StreamController<void>.broadcast(
    sync: true,
  );
  final Map<String, Completer<WebRtcPluginJson>> _requests =
      <String, Completer<WebRtcPluginJson>>{};
  var _requestId = 0;

  Stream<WebRtcPluginJson> get events => _events.stream;
  Stream<void> get disconnects => _disconnects.stream;

  Future<bool> connect() async {
    return await _channel.invokeMethod<bool>('connect') ?? false;
  }

  Future<bool> requestAudioPermission() async {
    return await _channel.invokeMethod<bool>('requestAudioPermission') ?? false;
  }

  Future<WebRtcPluginJson> request(
    String type, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    final requestId = 'voice_${_requestId++}';
    final completer = Completer<WebRtcPluginJson>();
    _requests[requestId] = completer;
    final raw = jsonEncode(<String, Object?>{
      'type': type,
      'requestId': requestId,
      ...arguments,
    });
    try {
      await _channel.invokeMethod<void>('request', <String, Object?>{
        'requestJson': raw,
      });
    } catch (_) {
      _requests.remove(requestId);
      rethrow;
    }
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _requests.remove(requestId);
        throw TimeoutException('WebRTC 插件请求超时：$type');
      },
    );
  }

  Future<void> disconnect() {
    return _channel.invokeMethod<void>('disconnect');
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onEvent':
        final raw = call.arguments as String?;
        if (raw == null || raw.isEmpty) return;
        final event = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final type = event['type'] as String?;
        final requestId = event['requestId'] as String?;
        if ((type == 'result' || type == 'error') && requestId != null) {
          final completer = _requests.remove(requestId);
          if (completer == null) return;
          if (type == 'error') {
            completer.completeError(
              StateError(event['message'] as String? ?? 'WebRTC 插件操作失败'),
            );
          } else {
            completer.complete(
              event['data'] is Map
                  ? Map<String, dynamic>.from(event['data'] as Map)
                  : <String, dynamic>{},
            );
          }
          return;
        }
        _events.add(event);
      case 'onDisconnected':
        _failPending(StateError('WebRTC 语音插件连接已断开'));
        _disconnects.add(null);
    }
  }

  void _failPending(Object error) {
    final pending = _requests.values.toList(growable: false);
    _requests.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    _failPending(StateError('WebRTC plugin gateway disposed'));
    await _events.close();
    await _disconnects.close();
  }
}
