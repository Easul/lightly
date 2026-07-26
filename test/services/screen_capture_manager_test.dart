import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/core/logging/runtime_logger.dart';
import 'package:lightly/features/remote_control/domain/remote_control_runtime.dart';
import 'package:lightly/features/remote_control/infrastructure/screen_capture_manager.dart';

void main() {
  test('uses injected capture platform and runtime logger', () async {
    final platformRuntime = _RecordingCapturePlatformRuntime();
    final logger = _RecordingRuntimeLogger();
    final manager = ScreenCaptureManager(
      platformRuntime: platformRuntime,
      runtimeLogger: logger,
    );

    expect(await manager.startCapture(fps: 12, bitrate: 2500000), isTrue);
    expect(platformRuntime.startArguments, (fps: 12, bitrate: 2500000));

    await manager.stopCapture();
    await Future<void>.delayed(Duration.zero);

    expect(platformRuntime.stopCount, 1);
    expect(logger.messages, contains('[ScreenCapture] Screen capture started'));
    expect(logger.messages, contains('[ScreenCapture] Screen capture stopped'));
    manager.dispose();
  });
}

class _RecordingCapturePlatformRuntime
    implements RemoteControlCapturePlatformRuntime {
  ({int fps, int bitrate})? startArguments;
  int stopCount = 0;

  @override
  Future<bool?> startScreenCapture({
    required int fps,
    required int bitrate,
  }) async {
    startArguments = (fps: fps, bitrate: bitrate);
    return true;
  }

  @override
  Future<void> stopScreenCapture() async {
    stopCount++;
  }

  @override
  Future<void> requestKeyFrame() async {}

  @override
  Future<void> updateBitrate(int bitrate) async {}
}

class _RecordingRuntimeLogger extends NoopRuntimeLogger {
  final List<String> messages = <String>[];

  @override
  Future<void> log(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) async {
    messages.add(message);
  }
}
