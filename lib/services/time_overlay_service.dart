import 'package:flutter/services.dart';

class TimeOverlayService {
  static const MethodChannel _channel = MethodChannel('time_overlay');

  Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('checkPermission') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> requestPermission() =>
      _channel.invokeMethod('requestPermission');

  Future<void> show() => _channel.invokeMethod('show');

  Future<void> close() => _channel.invokeMethod('close');

  Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
