import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'video_duration_formatter.dart';
import 'video_gesture_math.dart';

class FloatingVideoSurfaceGestureController {
  final ValueNotifier<String?> hint = ValueNotifier<String?>(null);
  final ValueNotifier<Duration?> previewPosition = ValueNotifier<Duration?>(
    null,
  );

  Timer? _hintTimer;
  double? _doubleTapLocalX;
  Duration? _horizontalSeekStart;
  Duration? _horizontalSeekDuration;
  double _horizontalDragDistance = 0;
  double _horizontalSurfaceWidth = 0;
  bool _longPressSpeedActive = false;
  double _longPressRestoreSpeed = 1.0;
  int _longPressSpeedGeneration = 0;

  void recordDoubleTapDown(double localX) {
    _doubleTapLocalX = localX;
  }

  VideoDoubleTapZone takeDoubleTapZone(double surfaceWidth) {
    final zone = classifyVideoDoubleTap(
      localX: _doubleTapLocalX ?? surfaceWidth / 2,
      surfaceWidth: surfaceWidth,
    );
    _doubleTapLocalX = null;
    return zone;
  }

  void seekByDoubleTap({
    required VideoPlayerController controller,
    required bool forward,
  }) {
    final value = controller.value;
    if (!value.isInitialized || value.duration <= Duration.zero) return;
    final target = offsetVideoPosition(
      position: value.position,
      duration: value.duration,
      offset: Duration(seconds: forward ? 5 : -5),
    );
    unawaited(controller.seekTo(target));
    showHint(
      '${forward ? '快进' : '快退'} 5 秒\n'
      '${formatVideoDuration(target)} / ${formatVideoDuration(value.duration)}',
    );
  }

  bool startHorizontalSeek({
    required VideoPlayerController? controller,
    required double surfaceWidth,
  }) {
    final value = controller?.value;
    if (value == null ||
        !value.isInitialized ||
        value.duration <= Duration.zero) {
      return false;
    }
    _horizontalSeekStart = value.position;
    _horizontalSeekDuration = value.duration;
    _horizontalDragDistance = 0;
    _horizontalSurfaceWidth = surfaceWidth;
    previewPosition.value = value.position;
    return true;
  }

  void updateHorizontalSeek(double primaryDelta) {
    final start = _horizontalSeekStart;
    final duration = _horizontalSeekDuration;
    if (start == null || duration == null) return;
    _horizontalDragDistance += primaryDelta;
    final target = horizontalSeekTarget(
      startPosition: start,
      duration: duration,
      dragDistance: _horizontalDragDistance,
      surfaceWidth: _horizontalSurfaceWidth,
    );
    previewPosition.value = target;
    final deltaMs = target.inMilliseconds - start.inMilliseconds;
    final delta = Duration(milliseconds: deltaMs.abs());
    showHint(
      '${deltaMs < 0 ? '快退' : '快进'} ${formatVideoDuration(delta)}\n'
      '${formatVideoDuration(target)} / ${formatVideoDuration(duration)}',
      autoHide: false,
    );
  }

  void finishHorizontalSeek(VideoPlayerController? controller) {
    final target = previewPosition.value;
    clearHorizontalSeek();
    if (target != null && controller != null) {
      unawaited(controller.seekTo(target));
    }
  }

  void clearHorizontalSeek() {
    _hintTimer?.cancel();
    hint.value = null;
    previewPosition.value = null;
    _horizontalSeekStart = null;
    _horizontalSeekDuration = null;
    _horizontalDragDistance = 0;
    _horizontalSurfaceWidth = 0;
  }

  void startLongPressSpeed(VideoPlayerController? controller) {
    final value = controller?.value;
    if (controller == null ||
        value == null ||
        !value.isInitialized ||
        !value.isPlaying ||
        _longPressSpeedActive) {
      return;
    }
    _longPressSpeedActive = true;
    _longPressRestoreSpeed = value.playbackSpeed;
    final generation = ++_longPressSpeedGeneration;
    showHint('3.0x 快进', autoHide: false);
    unawaited(_applyLongPressSpeed(controller, generation));
  }

  Future<void> _applyLongPressSpeed(
    VideoPlayerController controller,
    int generation,
  ) async {
    try {
      await controller.setPlaybackSpeed(3.0);
      if (!_longPressSpeedActive || generation != _longPressSpeedGeneration) {
        await controller.setPlaybackSpeed(_longPressRestoreSpeed);
      }
    } catch (_) {
      if (generation == _longPressSpeedGeneration) {
        _longPressSpeedActive = false;
        hint.value = null;
      }
    }
  }

  void restoreLongPressSpeed(VideoPlayerController? controller) {
    if (!_longPressSpeedActive) return;
    _longPressSpeedActive = false;
    _longPressSpeedGeneration++;
    _hintTimer?.cancel();
    hint.value = null;
    if (controller != null) {
      unawaited(
        controller.setPlaybackSpeed(_longPressRestoreSpeed).catchError((_) {}),
      );
    }
  }

  void showHint(String message, {bool autoHide = true}) {
    _hintTimer?.cancel();
    hint.value = message;
    if (!autoHide) return;
    _hintTimer = Timer(const Duration(milliseconds: 800), () {
      hint.value = null;
    });
  }

  void dispose(VideoPlayerController? controller) {
    _hintTimer?.cancel();
    restoreLongPressSpeed(controller);
    hint.dispose();
    previewPosition.dispose();
  }
}
