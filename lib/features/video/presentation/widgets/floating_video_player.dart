import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../domain/floating_video_system_ui_runtime.dart';
import 'floating_video_player_widget.dart';

/// 悬浮视频播放器模式
enum FloatingPlayerMode {
  /// 默认模式 - 全宽悬浮窗
  defaultMode,

  /// 小窗口模式 - 45%宽度
  mini,

  /// 横屏全屏模式
  fullscreen,
}

class FloatingVideoPlayerController {
  _FloatingVideoPlayerState? _state;

  FloatingPlayerMode get mode =>
      _state?._mode ?? FloatingPlayerMode.defaultMode;

  bool get isAttached => _state != null;

  bool get isFullscreen => mode == FloatingPlayerMode.fullscreen;

  void _attach(_FloatingVideoPlayerState state) {
    _state = state;
  }

  void _detach(_FloatingVideoPlayerState state) {
    if (_state == state) {
      _state = null;
    }
  }

  void exitFullscreenToDefault() {
    _state?._setMode(FloatingPlayerMode.defaultMode);
  }
}

/// A draggable floating video player that can be positioned anywhere on screen.
/// Uses Overlay to float above other widgets within the app.
class FloatingVideoPlayer extends StatefulWidget {
  const FloatingVideoPlayer({
    super.key,
    this.controller,
    required this.onClose,
    this.onDownload,
    this.isLooping = false,
    this.onLoopingChanged,
    this.title,
    this.initialPosition,
    this.isLoading = false,
    this.errorMessage,
    this.onModeChanged,
    this.playerController,
    required this.systemUiRuntime,
  });

  final VideoPlayerController? controller;
  final VoidCallback onClose;
  final VoidCallback? onDownload;
  final bool isLooping;
  final ValueChanged<bool>? onLoopingChanged;
  final String? title;
  final Offset? initialPosition;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<FloatingPlayerMode>? onModeChanged;
  final FloatingVideoPlayerController? playerController;
  final FloatingVideoSystemUiRuntime systemUiRuntime;

  static String? shortDisplayTitle(String? title) {
    final trimmed = title?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final chars = trimmed.characters;
    if (chars.length <= 6) {
      return trimmed;
    }
    return '${chars.take(6).toString()}…';
  }

  @override
  State<FloatingVideoPlayer> createState() => _FloatingVideoPlayerState();

  /// Shows the floating player as an overlay.
  static OverlayEntry show({
    required BuildContext context,
    VideoPlayerController? controller,
    required VoidCallback onClose,
    VoidCallback? onDownload,
    bool isLooping = false,
    ValueChanged<bool>? onLoopingChanged,
    String? title,
    Offset? initialPosition,
    bool isLoading = false,
    String? errorMessage,
    ValueChanged<FloatingPlayerMode>? onModeChanged,
    FloatingVideoPlayerController? playerController,
    required FloatingVideoSystemUiRuntime systemUiRuntime,
  }) {
    final overlay = OverlayEntry(
      builder: (context) => FloatingVideoPlayer(
        controller: controller,
        onClose: onClose,
        onDownload: onDownload,
        isLooping: isLooping,
        onLoopingChanged: onLoopingChanged,
        title: title,
        initialPosition: initialPosition,
        isLoading: isLoading,
        errorMessage: errorMessage,
        onModeChanged: onModeChanged,
        playerController: playerController,
        systemUiRuntime: systemUiRuntime,
      ),
    );
    Overlay.of(context).insert(overlay);
    return overlay;
  }
}

class _FloatingVideoPlayerState extends State<FloatingVideoPlayer>
    with WidgetsBindingObserver {
  late Offset _position;
  bool _isDragging = false;
  FloatingPlayerMode _mode = FloatingPlayerMode.defaultMode;
  bool _isLocked = false;
  late bool _isLooping;

  static const double _miniWidthFactor = 0.45;

  // Static counter to track active floating player instances.
  // Only disable wake lock when the last instance is disposed.
  static int _activeInstanceCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _position = widget.initialPosition ?? Offset(0, 0);
    _isLooping = widget.isLooping;
    widget.playerController?._attach(this);
    _activeInstanceCount++;
    _enableWakeLock();
    unawaited(widget.controller?.setLooping(_isLooping));
    unawaited(_applySystemUiForCurrentMode(immediate: true));
  }

  void _enableWakeLock() {
    WakelockPlus.enable();
    unawaited(_setKeepScreenOn(true));
  }

  void _disableWakeLockIfLast() {
    _activeInstanceCount--;
    if (_activeInstanceCount <= 0) {
      _activeInstanceCount = 0;
      WakelockPlus.disable();
      unawaited(_setKeepScreenOn(false));
    }
  }

  Future<void> _setKeepScreenOn(bool keepOn) async {
    try {
      await widget.systemUiRuntime.setKeepScreenOn(keepOn);
    } catch (_) {
      // Some platforms do not implement the optional window flag contract.
    }
  }

  Future<void> _applySystemUiForCurrentMode({bool immediate = false}) async {
    if (!mounted) return;

    Future<void> apply() async {
      if (!mounted) return;
      if (_isFullscreen) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      _enableWakeLock();
    }

    if (immediate) {
      await apply();
      return;
    }

    unawaited(Future<void>.delayed(const Duration(milliseconds: 300), apply));
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (_isFullscreen) {
      unawaited(_applySystemUiForCurrentMode());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_applySystemUiForCurrentMode(immediate: true));
    }
  }

  /// 获取当前模式
  FloatingPlayerMode get mode => _mode;

  /// 是否处于全屏模式
  bool get _isFullscreen => _mode == FloatingPlayerMode.fullscreen;

  /// 切换模式按钮点击处理
  /// 按钮逻辑：默认窗 <-> 横屏，小窗 -> 默认窗
  void _toggleMode() {
    switch (_mode) {
      case FloatingPlayerMode.defaultMode:
        _setMode(FloatingPlayerMode.fullscreen);
        break;
      case FloatingPlayerMode.mini:
        _setMode(FloatingPlayerMode.defaultMode);
        break;
      case FloatingPlayerMode.fullscreen:
        _setMode(FloatingPlayerMode.defaultMode);
        break;
    }
  }

  void _setMode(FloatingPlayerMode newMode) {
    setState(() {
      _mode = newMode;
      if (newMode == FloatingPlayerMode.defaultMode) {
        _position = Offset(0, _minY);
      }
    });

    widget.onModeChanged?.call(_mode);

    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    }

    unawaited(_applySystemUiForCurrentMode());
  }

  void _toggleLooping() {
    final nextValue = !_isLooping;
    setState(() {
      _isLooping = nextValue;
    });
    unawaited(widget.controller?.setLooping(nextValue));
    widget.onLoopingChanged?.call(nextValue);
  }

  /// 双击切换小窗模式
  void _toggleMiniMode() {
    if (_isFullscreen) return;

    setState(() {
      if (_mode == FloatingPlayerMode.mini) {
        _mode = FloatingPlayerMode.defaultMode;
        _position = Offset(0, _minY);
      } else {
        _mode = FloatingPlayerMode.mini;
      }
    });
    widget.onModeChanged?.call(_mode);
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
    });
  }

  double get _minY => MediaQuery.viewPaddingOf(context).top;

  double get _playerWidth {
    final screenW = MediaQuery.of(context).size.width;
    switch (_mode) {
      case FloatingPlayerMode.fullscreen:
        return screenW;
      case FloatingPlayerMode.mini:
        return screenW * _miniWidthFactor;
      case FloatingPlayerMode.defaultMode:
        return screenW;
    }
  }

  double get _playerHeight {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    switch (_mode) {
      case FloatingPlayerMode.fullscreen:
        return screenH;
      case FloatingPlayerMode.mini:
        return screenW * _miniWidthFactor * 9 / 16;
      case FloatingPlayerMode.defaultMode:
        return screenW * 9 / 16;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxY = size.height - _playerHeight - 80;
    final accentColor = Theme.of(context).colorScheme.primary;

    if (!_isFullscreen) {
      _position = _clampedPosition(_position, size, maxY);
    }

    return Positioned(
      left: _isFullscreen ? 0 : _position.dx,
      top: _isFullscreen ? 0 : _position.dy,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        width: _playerWidth,
        height: _playerHeight,
        child: Material(
          elevation: 8,
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: _mode == FloatingPlayerMode.mini && !_isLocked
                ? (_) {
                    setState(() {
                      _isDragging = true;
                    });
                  }
                : null,
            onPanUpdate: _mode == FloatingPlayerMode.mini && !_isLocked
                ? (details) {
                    final screenSize = MediaQuery.of(context).size;
                    final maxDragY = screenSize.height - _playerHeight - 80;
                    setState(() {
                      _position = _clampedPosition(
                        _position + details.delta,
                        screenSize,
                        maxDragY,
                      );
                    });
                  }
                : null,
            onPanEnd: _mode == FloatingPlayerMode.mini && !_isLocked
                ? (_) {
                    setState(() {
                      _isDragging = false;
                    });
                  }
                : null,
            onPanCancel: _mode == FloatingPlayerMode.mini && !_isLocked
                ? () {
                    setState(() {
                      _isDragging = false;
                    });
                  }
                : null,
            onVerticalDragStart:
                _mode == FloatingPlayerMode.defaultMode && !_isLocked
                ? (_) {
                    setState(() {
                      _isDragging = true;
                    });
                  }
                : null,
            onVerticalDragUpdate:
                _mode == FloatingPlayerMode.defaultMode && !_isLocked
                ? (details) {
                    final screenSize = MediaQuery.of(context).size;
                    final maxDragY = screenSize.height - _playerHeight - 80;
                    setState(() {
                      _position = _clampedPosition(
                        Offset(0, _position.dy + details.delta.dy),
                        screenSize,
                        maxDragY,
                      );
                    });
                  }
                : null,
            onVerticalDragEnd:
                _mode == FloatingPlayerMode.defaultMode && !_isLocked
                ? (_) {
                    setState(() {
                      _isDragging = false;
                    });
                  }
                : null,
            onVerticalDragCancel:
                _mode == FloatingPlayerMode.defaultMode && !_isLocked
                ? () {
                    setState(() {
                      _isDragging = false;
                    });
                  }
                : null,
            onDoubleTap: _mode == FloatingPlayerMode.mini
                ? _toggleMiniMode
                : null,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                border: _isDragging
                    ? Border.all(
                        color: accentColor.withValues(alpha: 0.55),
                        width: 2,
                      )
                    : null,
              ),
              child: FloatingVideoPlayerWidget(
                controller: widget.controller,
                title: widget.title,
                mode: _mode,
                isLocked: _isLocked,
                isLooping: _isLooping,
                isLoading: widget.isLoading,
                errorMessage: widget.errorMessage,
                onClose: widget.onClose,
                onModeToggle: _toggleMode,
                onLockToggle: _toggleLock,
                onLoopToggle: _toggleLooping,
                onCenterDoubleTap: _toggleMiniMode,
                onDownload: widget.onDownload,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset _clampedPosition(Offset position, Size size, double maxY) {
    final minX = _mode == FloatingPlayerMode.defaultMode ? 0.0 : 0.0;
    final maxX = _mode == FloatingPlayerMode.defaultMode
        ? 0.0
        : size.width - _playerWidth;
    return Offset(
      position.dx.clamp(minX, maxX),
      position.dy.clamp(_minY, maxY),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.playerController?._detach(this);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Disable screen wake lock only when the last floating player instance closes
    _disableWakeLockIfLast();
    super.dispose();
  }
}
