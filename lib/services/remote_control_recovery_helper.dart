import 'dart:math' as math;

class ScreenBitrateDecision {
  final int? newBitrate;
  final String? logMessage;

  const ScreenBitrateDecision({this.newBitrate, this.logMessage});
}

class ScreenRecoveryDecision {
  final bool shouldRequestKeyFrame;
  final String? logMessage;

  const ScreenRecoveryDecision({
    required this.shouldRequestKeyFrame,
    this.logMessage,
  });
}

class RemoteControlRecoveryHelper {
  const RemoteControlRecoveryHelper();

  int recommendedMinScreenBitrate(Map<String, dynamic>? screenInfo) {
    final width = (screenInfo?['width'] as num?)?.toInt();
    final height = (screenInfo?['height'] as num?)?.toInt();
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 1000000;
    }

    final pixels = width * height;
    if (pixels >= 2500000) {
      return 1400000;
    }
    if (pixels >= 1800000) {
      return 1000000;
    }
    return 800000;
  }

  ScreenBitrateDecision decideNextBitrate({
    required List<int> frameArrivalDelays,
    required int currentBitrate,
    required int maxBitrate,
    required int screenFps,
  }) {
    if (frameArrivalDelays.length < 10) {
      return const ScreenBitrateDecision();
    }

    final targetFps = screenFps.clamp(1, 60);
    final targetFrameIntervalMs = 1000 / targetFps;
    final congestionAvgThreshold = math.max(220.0, targetFrameIntervalMs * 4.0);
    final congestionMaxThreshold = math.max(
      900.0,
      targetFrameIntervalMs * 12.0,
    );
    final upgradeAvgThreshold = math.max(120.0, targetFrameIntervalMs * 1.8);
    final upgradeMaxThreshold = math.max(350.0, targetFrameIntervalMs * 4.5);
    final avgDelay =
        frameArrivalDelays.reduce((a, b) => a + b) / frameArrivalDelays.length;
    final maxDelay = frameArrivalDelays.reduce((a, b) => a > b ? a : b);

    if (maxDelay > congestionMaxThreshold ||
        avgDelay > congestionAvgThreshold) {
      final newBitrate = (currentBitrate * 0.85).round();
      return ScreenBitrateDecision(
        newBitrate: newBitrate,
        logMessage:
            '视频延迟高 (avg=${avgDelay.toStringAsFixed(1)}ms, max=$maxDelay ms, target=${targetFrameIntervalMs.toStringAsFixed(1)}ms), 降低码率至 $newBitrate',
      );
    }

    if (avgDelay < upgradeAvgThreshold &&
        maxDelay < upgradeMaxThreshold &&
        currentBitrate < maxBitrate) {
      var newBitrate = (currentBitrate * 1.25).round();
      if (newBitrate > maxBitrate) newBitrate = maxBitrate;
      return ScreenBitrateDecision(
        newBitrate: newBitrate,
        logMessage:
            '视频延迟良好 (avg=${avgDelay.toStringAsFixed(1)}ms, max=$maxDelay ms, target=${targetFrameIntervalMs.toStringAsFixed(1)}ms), 提升码率至 $newBitrate',
      );
    }

    return const ScreenBitrateDecision();
  }

  ScreenRecoveryDecision decideScreenRecovery({
    required DateTime now,
    required DateTime? lastKeyFrameRequestAt,
    required DateTime? lastScreenFrameTime,
    required DateTime? screenWatchdogStartedAt,
    required DateTime? lastScreenChunkTime,
    required bool awaitingRecoveryKeyFrame,
    required Duration screenRecoveryKeyFrameRetryCooldown,
    required Duration screenKeyFrameRequestCooldown,
    required Duration screenFrameStallThreshold,
    required int screenDataBufferLength,
    required int screenChunkCount,
    required int screenFrameCount,
  }) {
    final requestCooldown = awaitingRecoveryKeyFrame
        ? screenRecoveryKeyFrameRetryCooldown
        : screenKeyFrameRequestCooldown;
    if (lastKeyFrameRequestAt != null &&
        now.difference(lastKeyFrameRequestAt) < requestCooldown) {
      return const ScreenRecoveryDecision(shouldRequestKeyFrame: false);
    }

    final shouldRequest = lastScreenFrameTime != null
        ? now.difference(lastScreenFrameTime) >= screenFrameStallThreshold
        : screenWatchdogStartedAt != null &&
              now.difference(screenWatchdogStartedAt) >=
                  screenFrameStallThreshold;

    if (!shouldRequest) {
      return const ScreenRecoveryDecision(shouldRequestKeyFrame: false);
    }

    return ScreenRecoveryDecision(
      shouldRequestKeyFrame: true,
      logMessage:
          'Screen frame gap detected; requesting key frame: lastFrameAgo=${lastScreenFrameTime == null ? 'never' : '${now.difference(lastScreenFrameTime).inMilliseconds}ms'} watchdogAge=${screenWatchdogStartedAt == null ? 'unknown' : '${now.difference(screenWatchdogStartedAt).inMilliseconds}ms'} lastChunkAgo=${lastScreenChunkTime == null ? 'never' : '${now.difference(lastScreenChunkTime).inMilliseconds}ms'} buffered=$screenDataBufferLength chunkCount=$screenChunkCount frameCount=$screenFrameCount',
    );
  }
}
