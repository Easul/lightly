import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../services/app_log_service.dart';
import '../../domain/screen_frame.dart';
import '../../infrastructure/remote_control_platform_gateway.dart';
import '../../infrastructure/screen_capture_manager.dart';

class RemoteControlScreenViewer extends StatefulWidget {
  final Stream<ScreenFrame> frameStream;
  final Size remoteScreenSize;
  final Uint8List? initialSps;
  final Uint8List? initialPps;
  final Uint8List? Function()? latestSpsProvider;
  final Uint8List? Function()? latestPpsProvider;
  final Future<void> Function()? onViewerReady;
  final RemoteControlPlatformGateway? platformGateway;

  const RemoteControlScreenViewer({
    super.key,
    required this.frameStream,
    required this.remoteScreenSize,
    this.initialSps,
    this.initialPps,
    this.latestSpsProvider,
    this.latestPpsProvider,
    this.onViewerReady,
    this.platformGateway,
  });

  @override
  State<RemoteControlScreenViewer> createState() =>
      _RemoteControlScreenViewerState();
}

class _RemoteControlScreenViewerState extends State<RemoteControlScreenViewer> {
  late final RemoteControlPlatformGateway _platformGateway;

  late StreamSubscription<ScreenFrame> _frameSubscription;
  int? _textureId;
  bool _isInitialized = false;
  int _frameCount = 0;
  DateTime? _lastFrameTime;
  double _fps = 0;
  bool _hasPushedConfig = false;
  Timer? _configRetryTimer;
  final List<ScreenFrame> _pendingFrames = <ScreenFrame>[];
  final List<ScreenFrame> _pendingConfigFrames = <ScreenFrame>[];
  ScreenFrame? _pendingKeyFrame;
  ScreenFrame? _pendingDeltaFrame;
  bool _isPushingFrame = false;
  bool _hasDecodedReferenceFrame = false;
  bool _hasLoggedFramePushFailure = false;

  @override
  void initState() {
    super.initState();
    _platformGateway =
        widget.platformGateway ?? RemoteControlPlatformGateway.instance;
    _frameSubscription = widget.frameStream.listen(_handleFrame);
    _initTexture();
  }

  @override
  void dispose() {
    _configRetryTimer?.cancel();
    _frameSubscription.cancel();
    _disposeTexture();
    super.dispose();
  }

  Future<void> _initTexture() async {
    try {
      final textureId = await _platformGateway.createScreenTexture(
        width: widget.remoteScreenSize.width.round(),
        height: widget.remoteScreenSize.height.round(),
      );
      if (textureId != null) {
        setState(() {
          _textureId = textureId;
          _isInitialized = true;
        });
        await _pushInitialConfigIfAvailable();
        _startConfigRetryIfNeeded();
        await _flushPendingFrames();
        unawaited(widget.onViewerReady?.call());
        developer.log(
          'Screen texture created: $textureId',
          name: 'ScreenViewer',
        );
      }
    } catch (e, stackTrace) {
      recordRuntimeLog(
        'ScreenViewer',
        'Failed to create screen texture',
        error: e,
        stackTrace: stackTrace,
        metadata: <String, Object?>{
          'width': widget.remoteScreenSize.width.round(),
          'height': widget.remoteScreenSize.height.round(),
        },
      );
    }
  }

  Future<void> _pushInitialConfigIfAvailable() async {
    final sps = widget.latestSpsProvider?.call() ?? widget.initialSps;
    final pps = widget.latestPpsProvider?.call() ?? widget.initialPps;
    if (sps == null || pps == null) return;

    await _sendFrameToNative(
      ScreenFrame(
        type: ScreenFrameType.config,
        data: sps,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _sendFrameToNative(
      ScreenFrame(
        type: ScreenFrameType.config,
        data: pps,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _hasPushedConfig = true;
    _configRetryTimer?.cancel();
    unawaited(widget.onViewerReady?.call());
    developer.log(
      'Pushed cached decoder config: SPS=${sps.length} PPS=${pps.length}',
      name: 'ScreenViewer',
    );
  }

  void _startConfigRetryIfNeeded() {
    if (_hasPushedConfig) return;
    _configRetryTimer?.cancel();
    _configRetryTimer = Timer.periodic(const Duration(milliseconds: 300), (
      timer,
    ) async {
      if (!mounted || _hasPushedConfig || _textureId == null) {
        timer.cancel();
        return;
      }
      await _pushInitialConfigIfAvailable();
      if (_hasPushedConfig) {
        timer.cancel();
      }
    });
  }

  Future<void> _disposeTexture() async {
    if (_textureId == null) return;

    try {
      await _platformGateway.disposeScreenTexture(_textureId!);
    } catch (e, stackTrace) {
      recordRuntimeLog(
        'ScreenViewer',
        'Failed to dispose screen texture',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _handleFrame(ScreenFrame frame) {
    _frameCount++;

    final now = DateTime.now();
    if (_lastFrameTime != null) {
      final duration = now.difference(_lastFrameTime!).inMilliseconds;
      if (duration > 0) {
        _fps = 1000.0 / duration;
      }
    }
    _lastFrameTime = now;

    if (_textureId == null) {
      _bufferPendingFrame(frame);
      return;
    }

    _enqueueLatestFrame(frame);
  }

  void _bufferPendingFrame(ScreenFrame frame) {
    if (frame.type == ScreenFrameType.deltaFrame) {
      final hasReferenceFrame = _pendingFrames.any(
        (pending) => pending.type == ScreenFrameType.keyFrame,
      );
      if (!hasReferenceFrame) return;
    }

    _pendingFrames.add(frame);
    if (_pendingFrames.length > 24) {
      _pendingFrames.removeRange(0, _pendingFrames.length - 24);
    }
  }

  Future<void> _flushPendingFrames() async {
    if (_textureId == null || _pendingFrames.isEmpty) return;
    final frames = List<ScreenFrame>.from(_pendingFrames);
    _pendingFrames.clear();
    for (final frame in frames) {
      _queueFrame(frame);
    }
    await _pumpQueuedFrames();
  }

  void _enqueueLatestFrame(ScreenFrame frame) {
    _queueFrame(frame);
    unawaited(_pumpQueuedFrames());
  }

  void _queueFrame(ScreenFrame frame) {
    switch (frame.type) {
      case ScreenFrameType.config:
        _pendingConfigFrames.add(frame);
        if (_pendingConfigFrames.length > 2) {
          _pendingConfigFrames.removeRange(0, _pendingConfigFrames.length - 2);
        }
        _hasDecodedReferenceFrame = false;
        _pendingKeyFrame = null;
        _pendingDeltaFrame = null;
        break;
      case ScreenFrameType.keyFrame:
        _pendingKeyFrame = frame;
        _pendingDeltaFrame = null;
        break;
      case ScreenFrameType.deltaFrame:
        if (_pendingConfigFrames.isNotEmpty || _pendingKeyFrame != null) {
          return;
        }
        if (_pendingDeltaFrame != null || _isPushingFrame) {
          return;
        }
        if (!_hasDecodedReferenceFrame) {
          return;
        }
        _pendingDeltaFrame = frame;
        break;
    }
  }

  Future<void> _pumpQueuedFrames() async {
    if (_isPushingFrame || _textureId == null) return;
    _isPushingFrame = true;
    try {
      while (_textureId != null) {
        final nextFrame = _takeNextQueuedFrame();
        if (nextFrame == null) {
          break;
        }
        await _sendFrameToNative(nextFrame);
        if (nextFrame.type == ScreenFrameType.config) {
          _hasPushedConfig = true;
        } else if (nextFrame.type == ScreenFrameType.keyFrame) {
          _hasDecodedReferenceFrame = true;
        }
      }
    } finally {
      _isPushingFrame = false;
    }
  }

  ScreenFrame? _takeNextQueuedFrame() {
    if (_pendingConfigFrames.isNotEmpty) {
      if (_pendingKeyFrame == null) {
        return null;
      }
      return _pendingConfigFrames.removeAt(0);
    }
    if (_pendingKeyFrame != null) {
      final frame = _pendingKeyFrame;
      _pendingKeyFrame = null;
      return frame;
    }
    if (_pendingDeltaFrame != null) {
      final frame = _pendingDeltaFrame;
      _pendingDeltaFrame = null;
      return frame;
    }
    return null;
  }

  Future<void> _sendFrameToNative(ScreenFrame frame) async {
    if (_textureId == null) return;

    try {
      await _platformGateway.pushScreenFrame(
        textureId: _textureId!,
        data: frame.data,
        type: frame.type.index,
        timestamp: frame.timestamp,
      );
      _hasLoggedFramePushFailure = false;
    } catch (e, stackTrace) {
      if (_hasLoggedFramePushFailure) {
        developer.log(
          'Failed to push screen frame: $e',
          name: 'ScreenViewer',
          error: e,
        );
      } else {
        _hasLoggedFramePushFailure = true;
        recordRuntimeLog(
          'ScreenViewer',
          'Failed to push screen frame',
          error: e,
          stackTrace: stackTrace,
          metadata: <String, Object?>{
            'frameType': frame.type.name,
            'frameBytes': frame.data.length,
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _textureId == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('正在初始化屏幕...', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Texture(textureId: _textureId!),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_fps.toStringAsFixed(1)} FPS | $_frameCount frames',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }
}

class ScreenFrameDecoder {
  Uint8List? _sps;
  Uint8List? _pps;
  bool _isConfigured = false;

  bool get isConfigured => _isConfigured;

  void feedFrame(ScreenFrame frame) {
    switch (frame.type) {
      case ScreenFrameType.config:
        _parseConfig(frame.data);
        break;
      case ScreenFrameType.keyFrame:
        _handleKeyFrame(frame.data);
        break;
      case ScreenFrameType.deltaFrame:
        _handleDeltaFrame(frame.data);
        break;
    }
  }

  void _parseConfig(Uint8List data) {
    final nalUnits = ScreenCaptureManager.parseNalUnits(data);

    for (final unit in nalUnits) {
      final type = ScreenCaptureManager.getNalUnitType(unit);

      if (type == 7) {
        // SPS
        _sps = unit;
      } else if (type == 8) {
        // PPS
        _pps = unit;
      }
    }

    if (_sps != null && _pps != null) {
      _isConfigured = true;
    }
  }

  void _handleKeyFrame(Uint8List data) {
    if (!_isConfigured) {
      _parseConfig(data);
    }
  }

  void _handleDeltaFrame(Uint8List data) {
    if (!_isConfigured) return;
  }

  void reset() {
    _sps = null;
    _pps = null;
    _isConfigured = false;
  }
}
