import 'package:flutter/services.dart';

class BrowserFullscreenManager {
  bool _isInWebFullscreen = false;

  bool get isInWebFullscreen => _isInWebFullscreen;

  Future<void> enterWebFullscreen() async {
    _isInWebFullscreen = true;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> exitWebFullscreen() async {
    _isInWebFullscreen = false;
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
  }

  Future<void> restorePortraitIfNeeded() async {
    if (!_isInWebFullscreen) {
      return;
    }
    await exitWebFullscreen();
  }
}
