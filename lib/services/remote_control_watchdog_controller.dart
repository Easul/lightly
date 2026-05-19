import 'dart:async';
import 'dart:typed_data';

import 'remote_control_recovery_helper.dart';
import 'screen_capture_manager.dart';

class RemoteControlWatchdogController {
  final RemoteControlRecoveryHelper _recoveryHelper;

  RemoteControlWatchdogController({
    RemoteControlRecoveryHelper? recoveryHelper,
    int initialBitrate = 2500000,
  }) : _recoveryHelper = recoveryHelper ?? const RemoteControlRecoveryHelper(),
       _currentBitrate = initialBitrate;

  Timer? _screenFrameWatchdogTimer;
  Timer? _bitrateAdjustTimer;
  DateTime? _screenWatchdogStartedAt;
  DateTime? _lastKeyFrameRequestAt;
  DateTime? _lastScreenChunkTime;
  DateTime? _lastScreenChunkGapLogAt;
  int _screenChunkCount = 0;
  int _screenFrameCount = 0;
  bool _awaitingRecoveryKeyFrame = false;
  int _currentBitrate;
  final List<int> _frameArrivalDelays = [];
  DateTime? _lastScreenFrameTime;

  DateTime? get lastScreenFrameTime => _lastScreenFrameTime;
  DateTime? get lastScreenChunkTime => _lastScreenChunkTime;
  int get screenChunkCount => _screenChunkCount;
  int get screenFrameCount => _screenFrameCount;
  bool get awaitingRecoveryKeyFrame => _awaitingRecoveryKeyFrame;
  int get currentBitrate => _currentBitrate;

  void markAwaitingRecoveryKeyFrame([bool value = true]) {
    _awaitingRecoveryKeyFrame = value;
  }

  void recordKeyFrameRequest(DateTime requestedAt) {
    _lastKeyFrameRequestAt = requestedAt;
  }

  void recordScreenChunk({
    required Uint8List data,
    required int bufferedBefore,
    required void Function(String message) log,
  }) {
    final now = DateTime.now();
    final previousChunkAt = _lastScreenChunkTime;
    final chunkGapMs = previousChunkAt == null
        ? null
        : now.difference(previousChunkAt).inMilliseconds;
    _lastScreenChunkTime = now;
    _screenChunkCount++;
  }

  void recordParsedFrame({
    required ScreenFrame frame,
    required int remainingBuffer,
    required void Function(String message) log,
    required void Function() onBitrateAdjustDue,
  }) {
    _screenFrameCount++;

    final now = DateTime.now();
    if (_lastScreenFrameTime != null) {
      final delay = now.difference(_lastScreenFrameTime!).inMilliseconds;
      _frameArrivalDelays.add(delay);
      if (_frameArrivalDelays.length > 30) {
        _frameArrivalDelays.removeAt(0);
      }
    }
    _lastScreenFrameTime = now;

    if (_bitrateAdjustTimer == null || !_bitrateAdjustTimer!.isActive) {
      _bitrateAdjustTimer = Timer(
        const Duration(seconds: 2),
        onBitrateAdjustDue,
      );
    }
  }

  int? adjustBitrateIfNeeded({
    required int screenFps,
    required int maxBitrate,
    required Map<String, dynamic>? latestRemoteScreenInfo,
    required void Function(String message) log,
  }) {
    final decision = _recoveryHelper.decideNextBitrate(
      frameArrivalDelays: _frameArrivalDelays,
      currentBitrate: _currentBitrate,
      maxBitrate: maxBitrate,
      screenFps: screenFps,
    );
    final newBitrate = decision.newBitrate;
    if (newBitrate != null && newBitrate != _currentBitrate) {
      final minBitrateFloor = _recoveryHelper.recommendedMinScreenBitrate(
        latestRemoteScreenInfo,
      );
      _currentBitrate = newBitrate.clamp(minBitrateFloor, maxBitrate);
      _frameArrivalDelays.clear();
      return _currentBitrate;
    }
    return null;
  }

  void startScreenFrameWatchdog({
    required void Function(String message) log,
    required void Function() onTick,
    required Duration screenFrameStallThreshold,
    required Duration screenKeyFrameRequestCooldown,
    required Duration screenRecoveryKeyFrameRetryCooldown,
  }) {
    stopScreenFrameWatchdog(log: log, bufferLength: 0);
    _screenWatchdogStartedAt = DateTime.now();
    _screenFrameWatchdogTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => onTick(),
    );
  }

  void stopScreenFrameWatchdog({
    required void Function(String message) log,
    required int bufferLength,
  }) {
    _screenFrameWatchdogTimer?.cancel();
    _screenFrameWatchdogTimer = null;
    _screenWatchdogStartedAt = null;
    _lastKeyFrameRequestAt = null;
    _lastScreenFrameTime = null;
    _lastScreenChunkTime = null;
    _lastScreenChunkGapLogAt = null;
    _screenChunkCount = 0;
    _screenFrameCount = 0;
    _awaitingRecoveryKeyFrame = false;
  }

  bool checkScreenFrameHealth({
    required Duration screenRecoveryKeyFrameRetryCooldown,
    required Duration screenKeyFrameRequestCooldown,
    required Duration screenFrameStallThreshold,
    required int screenDataBufferLength,
    required void Function(String message) log,
  }) {
    final decision = _recoveryHelper.decideScreenRecovery(
      now: DateTime.now(),
      lastKeyFrameRequestAt: _lastKeyFrameRequestAt,
      lastScreenFrameTime: _lastScreenFrameTime,
      screenWatchdogStartedAt: _screenWatchdogStartedAt,
      lastScreenChunkTime: _lastScreenChunkTime,
      awaitingRecoveryKeyFrame: _awaitingRecoveryKeyFrame,
      screenRecoveryKeyFrameRetryCooldown: screenRecoveryKeyFrameRetryCooldown,
      screenKeyFrameRequestCooldown: screenKeyFrameRequestCooldown,
      screenFrameStallThreshold: screenFrameStallThreshold,
      screenDataBufferLength: screenDataBufferLength,
      screenChunkCount: _screenChunkCount,
      screenFrameCount: _screenFrameCount,
    );

    if (decision.shouldRequestKeyFrame) {
      _awaitingRecoveryKeyFrame = true;
    }
    return decision.shouldRequestKeyFrame;
  }
}
