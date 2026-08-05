import 'dart:math' as math;

enum VideoDoubleTapZone { rewind, center, forward }

Duration clampVideoPosition(Duration value, Duration duration) {
  if (duration <= Duration.zero) return Duration.zero;
  return Duration(
    milliseconds: value.inMilliseconds
        .clamp(0, duration.inMilliseconds)
        .toInt(),
  );
}

Duration offsetVideoPosition({
  required Duration position,
  required Duration duration,
  required Duration offset,
}) {
  return clampVideoPosition(position + offset, duration);
}

Duration horizontalSeekTarget({
  required Duration startPosition,
  required Duration duration,
  required double dragDistance,
  required double surfaceWidth,
}) {
  if (duration <= Duration.zero || surfaceWidth <= 0) {
    return clampVideoPosition(startPosition, duration);
  }
  final durationMs = duration.inMilliseconds;
  final adaptiveSpanMs = (durationMs * 0.1)
      .round()
      .clamp(
        const Duration(seconds: 30).inMilliseconds,
        const Duration(minutes: 10).inMilliseconds,
      )
      .toInt();
  final seekSpanMs = math.min(durationMs, adaptiveSpanMs);
  final deltaMs = (seekSpanMs * dragDistance / surfaceWidth).round();
  return clampVideoPosition(
    startPosition + Duration(milliseconds: deltaMs),
    duration,
  );
}

VideoDoubleTapZone classifyVideoDoubleTap({
  required double localX,
  required double surfaceWidth,
}) {
  if (surfaceWidth <= 0) return VideoDoubleTapZone.center;
  final fraction = (localX / surfaceWidth).clamp(0.0, 1.0);
  if (fraction < 0.4) return VideoDoubleTapZone.rewind;
  if (fraction > 0.6) return VideoDoubleTapZone.forward;
  return VideoDoubleTapZone.center;
}
