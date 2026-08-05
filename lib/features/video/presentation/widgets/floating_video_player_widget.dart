import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';

import '../floating_video_surface_gesture_controller.dart';
import '../video_gesture_math.dart';
import 'floating_video_player.dart';
import 'floating_video_player_controls.dart';

enum _GestureControlSide { brightness, volume }

class FloatingVideoPlayerWidget extends StatefulWidget {
  const FloatingVideoPlayerWidget({
    super.key,
    this.controller,
    this.onClose,
    this.onDownload,
    this.title,
    required this.mode,
    this.onModeToggle,
    this.isLocked = false,
    this.isLooping = false,
    this.onLockToggle,
    this.onLoopToggle,
    this.onCenterDoubleTap,
    this.isLoading = false,
    this.errorMessage,
  });

  final VideoPlayerController? controller;
  final VoidCallback? onClose;
  final VoidCallback? onDownload;
  final String? title;
  final FloatingPlayerMode mode;
  final VoidCallback? onModeToggle;
  final bool isLocked;
  final bool isLooping;
  final VoidCallback? onLockToggle;
  final VoidCallback? onLoopToggle;
  final VoidCallback? onCenterDoubleTap;
  final bool isLoading;
  final String? errorMessage;

  @override
  State<FloatingVideoPlayerWidget> createState() =>
      _FloatingVideoPlayerWidgetState();
}

class _FloatingVideoPlayerWidgetState extends State<FloatingVideoPlayerWidget> {
  static const double _gestureSensitivity = 320;

  bool _controlsVisible = true;
  Timer? _controlsTimer;
  double _brightness = 0.5;
  double _volume = 0.5;
  _GestureControlSide? _gestureSide;
  final FloatingVideoSurfaceGestureController _surfaceGestures =
      FloatingVideoSurfaceGestureController();
  bool _lockIndicatorVisible = true;
  Timer? _lockIndicatorTimer;
  bool _lastIsPlaying = false;
  bool _lastHasError = false;

  /// 是否处于全屏模式
  bool get _isFullscreen => widget.mode == FloatingPlayerMode.fullscreen;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerUpdate);
    _surfaceGestures.previewPosition.addListener(_onGesturePreviewChanged);
    _initializeSystemValues();
  }

  void _onGesturePreviewChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initializeSystemValues() async {
    try {
      final brightness = await ScreenBrightness().current;
      final volume = await VolumeController.instance.getVolume();
      if (!mounted) return;
      setState(() {
        _brightness = brightness;
        _volume = volume;
      });
    } catch (_) {}
  }

  void _onControllerUpdate() {
    final controller = widget.controller;
    final value = controller?.value;
    final isPlaying = value?.isPlaying ?? false;
    final hasError = value?.hasError ?? false;

    final didReachEnd =
        _lastIsPlaying &&
        !isPlaying &&
        value != null &&
        value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration - const Duration(milliseconds: 300);
    final didEnterError = !_lastHasError && hasError;
    final didStartPlaying = !_lastIsPlaying && isPlaying;

    _lastIsPlaying = isPlaying;
    _lastHasError = hasError;

    if (!mounted) {
      return;
    }

    if (didStartPlaying && !_controlsTimerActive) {
      _showControlsTemporarily();
      return;
    }

    if (didReachEnd || didEnterError) {
      _controlsTimer?.cancel();
      _lockIndicatorTimer?.cancel();
      setState(() {
        _controlsVisible = true;
        _lockIndicatorVisible = true;
      });
      return;
    }

    setState(() {});
  }

  @override
  void didUpdateWidget(covariant FloatingVideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerUpdate);
      widget.controller?.addListener(_onControllerUpdate);
      _surfaceGestures.restoreLongPressSpeed(oldWidget.controller);
      _surfaceGestures.clearHorizontalSeek();
    }
    if ((oldWidget.mode != widget.mode &&
            widget.mode == FloatingPlayerMode.mini) ||
        (!oldWidget.isLocked && widget.isLocked)) {
      _surfaceGestures.restoreLongPressSpeed(widget.controller);
      _surfaceGestures.clearHorizontalSeek();
    }
    if (widget.mode != oldWidget.mode ||
        widget.isLocked != oldWidget.isLocked) {
      if (widget.isLocked) {
        _showLockIndicatorTemporarily();
      } else {
        _showControlsTemporarily();
      }
    }
  }

  bool get _controlsTimerActive => _controlsTimer?.isActive == true;

  void _showControlsTemporarily() {
    if (widget.isLocked) return;
    setState(() {
      _controlsVisible = true;
    });
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted &&
          widget.controller?.value.isPlaying == true &&
          !widget.isLocked) {
        _hideControls();
      }
    });
  }

  void _hideControls() {
    _controlsTimer?.cancel();
    if (mounted && _controlsVisible) {
      setState(() {
        _controlsVisible = false;
      });
    }
  }

  void _handleSurfaceTap() {
    if (widget.isLocked) {
      _showLockIndicatorTemporarily();
      return;
    }
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControlsTemporarily();
    }
  }

  /// Show lock indicator when locked mode is tapped
  void _showLockIndicatorTemporarily() {
    if (!widget.isLocked) return;
    setState(() {
      _lockIndicatorVisible = true;
    });
    _lockIndicatorTimer?.cancel();
    _lockIndicatorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.isLocked) {
        setState(() {
          _lockIndicatorVisible = false;
        });
      }
    });
  }

  void _togglePlayPause() {
    if (widget.isLocked) return;
    final controller = widget.controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    _showControlsTemporarily();
  }

  double _getBufferedPosition(VideoPlayerValue value) {
    final duration = value.duration;
    if (!value.isInitialized ||
        duration <= Duration.zero ||
        value.buffered.isEmpty) {
      return 0;
    }

    final maxBufferedMs = value.buffered.fold<int>(0, (maxValue, range) {
      return math.max(maxValue, range.end.inMilliseconds);
    });
    return maxBufferedMs.clamp(0, duration.inMilliseconds).toDouble();
  }

  void _startGesture(DragStartDetails details, double maxWidth) {
    if (widget.isLocked) return;
    final isLeft = details.localPosition.dx < maxWidth / 2;
    _gestureSide = isLeft
        ? _GestureControlSide.brightness
        : _GestureControlSide.volume;
  }

  void _updateGesture(DragUpdateDetails details) {
    final side = _gestureSide;
    if (side == null) return;

    final delta = -(details.primaryDelta ?? 0) / _gestureSensitivity;
    final currentValue = side == _GestureControlSide.brightness
        ? _brightness
        : _volume;
    final nextValue = (currentValue + delta).clamp(0.0, 1.0);

    if (side == _GestureControlSide.brightness) {
      _applyBrightness(nextValue);
    } else {
      _applyVolume(nextValue);
    }
  }

  void _endGesture() {
    _gestureSide = null;
    _surfaceGestures.hint.value = null;
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _surfaceGestures.recordDoubleTapDown(details.localPosition.dx);
  }

  void _handleDoubleTap() {
    if (widget.isLocked) return;
    final box = context.findRenderObject() as RenderBox?;
    final zone = _surfaceGestures.takeDoubleTapZone(box?.size.width ?? 0);
    if (zone == VideoDoubleTapZone.center) {
      widget.onCenterDoubleTap?.call();
      return;
    }
    final controller = widget.controller;
    if (controller == null) return;
    _surfaceGestures.seekByDoubleTap(
      controller: controller,
      forward: zone == VideoDoubleTapZone.forward,
    );
    _showControlsTemporarily();
  }

  void _startHorizontalSeek(DragStartDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    final started = _surfaceGestures.startHorizontalSeek(
      controller: widget.controller,
      surfaceWidth: box?.size.width ?? 0,
    );
    if (!started) return;
    _controlsTimer?.cancel();
    setState(() {
      _controlsVisible = true;
    });
  }

  void _updateHorizontalSeek(DragUpdateDetails details) {
    _surfaceGestures.updateHorizontalSeek(details.primaryDelta ?? 0);
  }

  void _endHorizontalSeek() {
    _surfaceGestures.finishHorizontalSeek(widget.controller);
    _showControlsTemporarily();
  }

  void _cancelHorizontalSeek() {
    _surfaceGestures.clearHorizontalSeek();
    _showControlsTemporarily();
  }

  void _startLongPressSpeed(LongPressStartDetails details) {
    _surfaceGestures.startLongPressSpeed(widget.controller);
  }

  void _endLongPressSpeed() {
    _surfaceGestures.restoreLongPressSpeed(widget.controller);
  }

  void _applyBrightness(double value) {
    if ((_brightness - value).abs() < 0.005) return;
    _brightness = value;
    _surfaceGestures.showHint('亮度 ${(value * 100).round()}%', autoHide: false);
    unawaited(ScreenBrightness().setScreenBrightness(value));
  }

  void _applyVolume(double value) {
    if ((_volume - value).abs() < 0.005) return;
    _volume = value;
    _surfaceGestures.showHint('音量 ${(value * 100).round()}%', autoHide: false);
    unawaited(VolumeController.instance.setVolume(value));
  }

  /// 根据当前模式返回模式切换按钮的图标
  /// - 默认窗/小窗: fullscreen (可进入横屏)
  /// - 横屏: fullscreen_exit (可退出横屏)
  IconData _getModeToggleIcon() {
    if (_isFullscreen) {
      return Icons.fullscreen_exit;
    }
    return Icons.fullscreen;
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _lockIndicatorTimer?.cancel();
    _surfaceGestures.previewPosition.removeListener(_onGesturePreviewChanged);
    _surfaceGestures.dispose(widget.controller);
    widget.controller?.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == FloatingPlayerMode.mini &&
        (widget.isLoading ||
            widget.errorMessage != null ||
            widget.controller == null)) {
      return ColoredBox(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [_buildMiniCloseButton()]),
      );
    }

    if (widget.isLoading) {
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('正在解析视频...', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            _buildLoadingControls(context),
          ],
        ),
      );
    }

    if (widget.errorMessage != null) {
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.errorMessage!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            _buildLoadingControls(context),
          ],
        ),
      );
    }

    final controller = widget.controller;
    if (controller == null) {
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Center(child: CircularProgressIndicator(color: Colors.white)),
            _buildLoadingControls(context),
          ],
        ),
      );
    }

    final value = controller.value;
    final hasError = value.hasError;
    final isInitialized = value.isInitialized;
    final displayPosition =
        _surfaceGestures.previewPosition.value ?? value.position;
    final surfaceGesturesEnabled =
        !widget.isLocked && widget.mode != FloatingPlayerMode.mini;

    return GestureDetector(
      dragStartBehavior: DragStartBehavior.down,
      onTap: _handleSurfaceTap,
      onDoubleTapDown: widget.isLocked || widget.mode == FloatingPlayerMode.mini
          ? null
          : _handleDoubleTapDown,
      onDoubleTap: widget.isLocked || widget.mode == FloatingPlayerMode.mini
          ? null
          : _handleDoubleTap,
      onHorizontalDragStart: surfaceGesturesEnabled
          ? _startHorizontalSeek
          : null,
      onHorizontalDragUpdate: surfaceGesturesEnabled
          ? _updateHorizontalSeek
          : null,
      onHorizontalDragEnd: surfaceGesturesEnabled
          ? (_) => _endHorizontalSeek()
          : null,
      onHorizontalDragCancel: surfaceGesturesEnabled
          ? _cancelHorizontalSeek
          : null,
      onLongPressStart: surfaceGesturesEnabled ? _startLongPressSpeed : null,
      onLongPressEnd: surfaceGesturesEnabled
          ? (_) => _endLongPressSpeed()
          : null,
      onLongPressCancel: surfaceGesturesEnabled ? _endLongPressSpeed : null,
      onVerticalDragStart: _isFullscreen && !widget.isLocked
          ? (details) {
              final box = context.findRenderObject() as RenderBox?;
              _startGesture(
                details,
                box?.size.width ?? MediaQuery.of(context).size.width,
              );
            }
          : null,
      onVerticalDragUpdate: _isFullscreen && !widget.isLocked
          ? _updateGesture
          : null,
      onVerticalDragEnd: _isFullscreen && !widget.isLocked
          ? (_) => _endGesture()
          : null,
      onVerticalDragCancel: _isFullscreen && !widget.isLocked
          ? _endGesture
          : null,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isInitialized && !hasError)
              Center(
                child: AspectRatio(
                  aspectRatio: value.aspectRatio > 0
                      ? value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(controller),
                ),
              )
            else if (hasError)
              const Center(
                child: Text('播放失败', style: TextStyle(color: Colors.white)),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            if (hasError && !isInitialized) _buildLoadingControls(context),

            if (isInitialized &&
                !widget.isLocked &&
                widget.mode == FloatingPlayerMode.mini)
              _buildMiniCloseButton(),

            if (isInitialized &&
                !widget.isLocked &&
                widget.mode != FloatingPlayerMode.mini)
              IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: FloatingVideoControlsOverlay(
                    title: widget.title,
                    mode: widget.mode,
                    isLocked: widget.isLocked,
                    isFullscreen: _isFullscreen,
                    isLooping: widget.isLooping,
                    isPlaying: value.isPlaying,
                    position: displayPosition,
                    duration: value.duration,
                    bufferedPosition: _getBufferedPosition(value),
                    modeToggleIcon: _getModeToggleIcon(),
                    onTogglePlayPause: _togglePlayPause,
                    onSeek: controller.seekTo,
                    onShowControls: _showControlsTemporarily,
                    onClose: widget.onClose,
                    onDownload: widget.onDownload,
                    onModeToggle: widget.onModeToggle,
                    onLockToggle: widget.onLockToggle,
                    onLoopToggle: widget.onLoopToggle,
                  ),
                ),
              ),

            // Lock indicator - shows briefly on tap when locked, tap to unlock
            if (widget.isLocked)
              FloatingVideoLockOverlay(
                visible: _lockIndicatorVisible,
                onWake: _showLockIndicatorTemporarily,
                onUnlock: widget.onLockToggle,
              ),

            FloatingVideoGestureHint(
              gestureHintListenable: _surfaceGestures.hint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingControls(BuildContext context) {
    if (widget.mode == FloatingPlayerMode.mini) {
      return _buildMiniCloseButton();
    }
    return FloatingVideoLoadingControls(
      title: widget.title,
      mode: widget.mode,
      isLocked: widget.isLocked,
      isFullscreen: _isFullscreen,
      isLooping: widget.isLooping,
      modeToggleIcon: _getModeToggleIcon(),
      onClose: widget.onClose,
      onDownload: widget.onDownload,
      onModeToggle: widget.onModeToggle,
      onLockToggle: widget.onLockToggle,
      onLoopToggle: widget.onLoopToggle,
    );
  }

  Widget _buildMiniCloseButton() {
    return Positioned(
      top: 4,
      right: 4,
      child: IconButton(
        tooltip: '关闭',
        onPressed: widget.onClose,
        icon: const Icon(Icons.close, color: Colors.white, size: 20),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
