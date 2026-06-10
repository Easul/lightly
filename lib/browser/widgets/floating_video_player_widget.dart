import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';

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
    this.onLockToggle,
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
  final VoidCallback? onLockToggle;
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
  final ValueNotifier<String?> _gestureHintNotifier = ValueNotifier(null);
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
    _initializeSystemValues();
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
    _gestureHintNotifier.value = null;
  }

  void _applyBrightness(double value) {
    if ((_brightness - value).abs() < 0.005) return;
    _brightness = value;
    _gestureHintNotifier.value = '亮度 ${(value * 100).round()}%';
    unawaited(ScreenBrightness().setScreenBrightness(value));
  }

  void _applyVolume(double value) {
    if ((_volume - value).abs() < 0.005) return;
    _volume = value;
    _gestureHintNotifier.value = '音量 ${(value * 100).round()}%';
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
    _gestureHintNotifier.dispose();
    widget.controller?.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    return GestureDetector(
      onTap: _handleSurfaceTap,
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

            if (isInitialized && !widget.isLocked)
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
                    isPlaying: value.isPlaying,
                    position: value.position,
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
              gestureHintListenable: _gestureHintNotifier,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingControls(BuildContext context) {
    return FloatingVideoLoadingControls(
      title: widget.title,
      mode: widget.mode,
      isLocked: widget.isLocked,
      isFullscreen: _isFullscreen,
      modeToggleIcon: _getModeToggleIcon(),
      onClose: widget.onClose,
      onDownload: widget.onDownload,
      onModeToggle: widget.onModeToggle,
      onLockToggle: widget.onLockToggle,
    );
  }
}
