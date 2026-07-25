import 'package:flutter/services.dart';

import '../features/ai/ai_config.dart';

class TranslationOverlayService {
  static const MethodChannel _channel = MethodChannel('translation_overlay');

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('checkPermission') ?? false;

  Future<void> requestPermission() =>
      _channel.invokeMethod<void>('requestPermission');

  Future<void> show(AiConfig config) =>
      _channel.invokeMethod<void>('show', config.toJson());

  Future<void> close() => _channel.invokeMethod<void>('close');

  Future<bool> isRunning() async =>
      await _channel.invokeMethod<bool>('isRunning') ?? false;
}
