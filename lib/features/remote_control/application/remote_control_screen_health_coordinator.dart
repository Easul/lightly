import 'dart:typed_data';

import '../domain/screen_frame.dart';
import 'remote_control_watchdog_controller.dart';

class RemoteControlScreenHealthCoordinator {
  RemoteControlScreenHealthCoordinator({
    RemoteControlWatchdogController? watchdog,
  }) : _watchdog = watchdog ?? RemoteControlWatchdogController();

  final RemoteControlWatchdogController _watchdog;

  bool get awaitingRecoveryKeyFrame => _watchdog.awaitingRecoveryKeyFrame;

  String get lastFrameAgeDescription {
    final lastFrameTime = _watchdog.lastScreenFrameTime;
    if (lastFrameTime == null) {
      return 'never';
    }
    return '${DateTime.now().difference(lastFrameTime).inMilliseconds}ms';
  }

  void recordKeyFrameRequest(DateTime requestedAt) {
    _watchdog.recordKeyFrameRequest(requestedAt);
  }

  void recordScreenChunk({
    required Uint8List data,
    required int bufferedBefore,
    required void Function(String message) log,
  }) {
    _watchdog.recordScreenChunk(
      data: data,
      bufferedBefore: bufferedBefore,
      log: log,
    );
  }

  void markAwaitingRecoveryKeyFrame(bool value) {
    _watchdog.markAwaitingRecoveryKeyFrame(value);
  }

  void recordParsedFrame({
    required ScreenFrame frame,
    required int remainingBuffer,
    required void Function(String message) log,
    required void Function() onBitrateAdjustDue,
  }) {
    _watchdog.recordParsedFrame(
      frame: frame,
      remainingBuffer: remainingBuffer,
      log: log,
      onBitrateAdjustDue: onBitrateAdjustDue,
    );
  }

  int? adjustBitrateIfNeeded({
    required int screenFps,
    required int maxBitrate,
    required Map<String, dynamic>? latestRemoteScreenInfo,
    required void Function(String message) log,
  }) {
    return _watchdog.adjustBitrateIfNeeded(
      screenFps: screenFps,
      maxBitrate: maxBitrate,
      latestRemoteScreenInfo: latestRemoteScreenInfo,
      log: log,
    );
  }

  void startWatchdog({
    required void Function(String message) log,
    required void Function() onTick,
    required Duration screenFrameStallThreshold,
    required Duration screenKeyFrameRequestCooldown,
    required Duration screenRecoveryKeyFrameRetryCooldown,
  }) {
    _watchdog.startScreenFrameWatchdog(
      log: log,
      onTick: onTick,
      screenFrameStallThreshold: screenFrameStallThreshold,
      screenKeyFrameRequestCooldown: screenKeyFrameRequestCooldown,
      screenRecoveryKeyFrameRetryCooldown: screenRecoveryKeyFrameRetryCooldown,
    );
  }

  void stopWatchdog({
    required void Function(String message) log,
    required int bufferLength,
  }) {
    _watchdog.stopScreenFrameWatchdog(log: log, bufferLength: bufferLength);
  }

  bool shouldRequestKeyFrame({
    required Duration screenRecoveryKeyFrameRetryCooldown,
    required Duration screenKeyFrameRequestCooldown,
    required Duration screenFrameStallThreshold,
    required int screenDataBufferLength,
    required void Function(String message) log,
  }) {
    return _watchdog.checkScreenFrameHealth(
      screenRecoveryKeyFrameRetryCooldown: screenRecoveryKeyFrameRetryCooldown,
      screenKeyFrameRequestCooldown: screenKeyFrameRequestCooldown,
      screenFrameStallThreshold: screenFrameStallThreshold,
      screenDataBufferLength: screenDataBufferLength,
      log: log,
    );
  }
}
