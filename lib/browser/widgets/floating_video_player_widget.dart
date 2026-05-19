import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';

import 'floating_video_player.dart';

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
  double _gestureBaseValue = 0.5;
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

    _lastIsPlaying = isPlaying;
    _lastHasError = hasError;

    if (!mounted) {
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
      _showControlsTemporarily();
    }
  }

  void _showControlsTemporarily() {
    if (widget.isLocked) return;
    setState(() {
      _controlsVisible = true;
    });
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          widget.controller?.value.isPlaying == true &&
          !widget.isLocked) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  /// Show lock indicator when locked mode is tapped
  void _showLockIndicatorTemporarily() {
    if (!widget.isLocked) return;
    setState(() {
      _lockIndicatorVisible = true;
    });
    _lockIndicatorTimer?.cancel();
    _lockIndicatorTimer = Timer(const Duration(seconds: 2), () {
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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  double get _modeIconSize => widget.mode == FloatingPlayerMode.mini ? 18 : 28;

  BoxConstraints get _modeButtonConstraints =>
      widget.mode == FloatingPlayerMode.mini
      ? const BoxConstraints(minWidth: 32, minHeight: 32)
      : const BoxConstraints(minWidth: 48, minHeight: 48);

  double get _titleFontSize => widget.mode == FloatingPlayerMode.mini ? 12 : 14;

  double get _timeFontSize => widget.mode == FloatingPlayerMode.mini ? 10 : 12;

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
                  Text(
                    '正在解析视频...',
                    style: const TextStyle(color: Colors.white),
                  ),
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
      onTap: _showControlsTemporarily,
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
                child: Text(
                  '播放失败',
                  style: const TextStyle(color: Colors.white),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            if (isInitialized && !widget.isLocked)
              IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Only allow brightness/volume gestures in fullscreen mode
                      final enableGestureControls = _isFullscreen;
                      return GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragStart: enableGestureControls
                            ? (details) =>
                                  _startGesture(details, constraints.maxWidth)
                            : null,
                        onVerticalDragUpdate: enableGestureControls
                            ? _updateGesture
                            : null,
                        onVerticalDragEnd: enableGestureControls
                            ? (_) => _endGesture()
                            : null,
                        onVerticalDragCancel: enableGestureControls
                            ? _endGesture
                            : null,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.6),
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.6),
                              ],
                              stops: const [0.0, 0.2, 0.7, 1.0],
                            ),
                          ),
                          child: Column(
                            children: [
                              _buildTopBar(context),
                              Expanded(
                                child: Center(
                                  child: GestureDetector(
                                    onTap: _togglePlayPause,
                                    child: Container(
                                      width:
                                          widget.mode == FloatingPlayerMode.mini
                                          ? 52
                                          : 64,
                                      height:
                                          widget.mode == FloatingPlayerMode.mini
                                          ? 52
                                          : 64,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.5,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        value.isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: Colors.white,
                                        size:
                                            widget.mode ==
                                                FloatingPlayerMode.mini
                                            ? 28
                                            : 36,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildBottomBar(),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

            // Lock indicator - shows briefly on tap when locked, tap to unlock
            // Invisible tap area to wake up lock indicator
            if (widget.isLocked && !_lockIndicatorVisible)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _showLockIndicatorTemporarily,
                  child: Container(color: Colors.transparent),
                ),
              ),

            // Visible lock icon that can be tapped to unlock
            if (widget.isLocked && _lockIndicatorVisible)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _showLockIndicatorTemporarily,
                  child: Container(
                    color: Colors.transparent,
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Center(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onLockToggle,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(16),
                            child: const Icon(
                              Icons.lock,
                              color: Colors.white70,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<String?>(
                  valueListenable: _gestureHintNotifier,
                  builder: (context, gestureHint, child) {
                    if (gestureHint == null) return const SizedBox.shrink();
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          gestureHint,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingControls(BuildContext context) {
    final topPadding = 0.0;
    final displayTitle = FloatingVideoPlayer.shortDisplayTitle(widget.title);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: topPadding + 4,
          left: 8,
          right: 8,
          child: Row(
            children: [
              if (displayTitle != null)
                Expanded(
                  child: Text(
                    displayTitle,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _titleFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (widget.onLockToggle != null && _isFullscreen)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      widget.isLocked ? Icons.lock : Icons.lock_open,
                      color: Colors.white,
                      size: _modeIconSize,
                    ),
                    onPressed: widget.onLockToggle,
                    padding: EdgeInsets.zero,
                    constraints: _modeButtonConstraints,
                  ),
                ),
              if (widget.onDownload != null)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.download_rounded,
                      color: Colors.white,
                      size: _modeIconSize,
                    ),
                    onPressed: widget.onDownload,
                    padding: EdgeInsets.zero,
                    constraints: _modeButtonConstraints,
                  ),
                ),
              if (widget.onClose != null)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: _modeIconSize,
                    ),
                    onPressed: widget.onClose,
                    padding: EdgeInsets.zero,
                    constraints: _modeButtonConstraints,
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: widget.onModeToggle != null
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _getModeToggleIcon(),
                      color: Colors.white,
                      size: _modeIconSize,
                    ),
                    onPressed: widget.onModeToggle,
                    padding: EdgeInsets.zero,
                    constraints: _modeButtonConstraints,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final topPadding = 0.0;
    final displayTitle = FloatingVideoPlayer.shortDisplayTitle(widget.title);
    return Container(
      padding: EdgeInsets.fromLTRB(8, topPadding + 4, 8, 4),
      child: Row(
        children: [
          if (displayTitle != null)
            Expanded(
              child: Text(
                displayTitle,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _titleFontSize,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (widget.onLockToggle != null && _isFullscreen)
            IconButton(
              icon: Icon(
                widget.isLocked ? Icons.lock : Icons.lock_open,
                color: Colors.white,
                size: _modeIconSize,
              ),
              onPressed: widget.onLockToggle,
              padding: EdgeInsets.zero,
              constraints: _modeButtonConstraints,
            ),
          if (widget.onDownload != null)
            IconButton(
              icon: Icon(
                Icons.download_rounded,
                color: Colors.white,
                size: _modeIconSize,
              ),
              onPressed: widget.onDownload,
              padding: EdgeInsets.zero,
              constraints: _modeButtonConstraints,
            ),
          if (widget.onClose != null)
            IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: _modeIconSize),
              onPressed: widget.onClose,
              padding: EdgeInsets.zero,
              constraints: _modeButtonConstraints,
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final controller = widget.controller;
    if (controller == null) return const SizedBox.shrink();
    final accentColor = Theme.of(context).colorScheme.primary;
    final value = controller.value;
    final position = value.position;
    final duration = value.duration ?? Duration.zero;
    final bufferedPosition = _getBufferedPosition(value);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (duration > Duration.zero)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: accentColor,
                secondaryActiveTrackColor: Colors.white.withValues(alpha: 0.92),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                thumbColor: accentColor,
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: position.inMilliseconds
                    .clamp(0, duration.inMilliseconds)
                    .toDouble(),
                max: duration.inMilliseconds.toDouble(),
                secondaryTrackValue: bufferedPosition,
                onChanged: (value) {
                  controller.seekTo(Duration(milliseconds: value.toInt()));
                  _showControlsTemporarily();
                },
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(color: Colors.white, fontSize: _timeFontSize),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _timeFontSize,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.onModeToggle != null)
                    IconButton(
                      icon: Icon(
                        _getModeToggleIcon(),
                        color: Colors.white,
                        size: _modeIconSize,
                      ),
                      onPressed: widget.onModeToggle,
                      padding: EdgeInsets.zero,
                      constraints: _modeButtonConstraints,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
