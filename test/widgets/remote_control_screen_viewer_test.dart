import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/core/logging/runtime_logger.dart';
import 'package:lightly/features/remote_control/domain/remote_control_runtime.dart';
import 'package:lightly/features/remote_control/domain/screen_frame.dart';
import 'package:lightly/features/remote_control/presentation/widgets/remote_control_screen_viewer.dart';

void main() {
  testWidgets('viewer forwards the original frame through injected runtime', (
    tester,
  ) async {
    final frames = StreamController<ScreenFrame>.broadcast();
    final platformRuntime = _RecordingScreenPlatformRuntime();
    final frameData = Uint8List.fromList(<int>[0, 0, 0, 1, 0x65, 1, 2, 3]);

    await tester.pumpWidget(
      MaterialApp(
        home: RemoteControlScreenViewer(
          frameStream: frames.stream,
          remoteScreenSize: const Size(720, 1280),
          initialSps: Uint8List.fromList(<int>[0, 0, 0, 1, 0x67]),
          initialPps: Uint8List.fromList(<int>[0, 0, 0, 1, 0x68]),
          platformRuntime: platformRuntime,
          runtimeLogger: const NoopRuntimeLogger(),
        ),
      ),
    );
    await tester.pump();

    expect(platformRuntime.createdSize, const Size(720, 1280));

    frames.add(
      ScreenFrame(
        type: ScreenFrameType.keyFrame,
        data: frameData,
        timestamp: 123,
      ),
    );
    await tester.pump();

    expect(platformRuntime.pushedFrames.last, same(frameData));
    expect(platformRuntime.pushedTimestamps.last, 123);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(platformRuntime.disposedTextureIds, <int>[7]);
    await frames.close();
  });
}

class _RecordingScreenPlatformRuntime
    implements RemoteControlScreenPlatformRuntime {
  Size? createdSize;
  final List<Uint8List> pushedFrames = <Uint8List>[];
  final List<int> pushedTimestamps = <int>[];
  final List<int> disposedTextureIds = <int>[];

  @override
  Future<int?> createScreenTexture({
    required int width,
    required int height,
  }) async {
    createdSize = Size(width.toDouble(), height.toDouble());
    return 7;
  }

  @override
  Future<void> disposeScreenTexture(int textureId) async {
    disposedTextureIds.add(textureId);
  }

  @override
  Future<void> pushScreenFrame({
    required int textureId,
    required Uint8List data,
    required int type,
    required int timestamp,
  }) async {
    expect(textureId, 7);
    pushedFrames.add(data);
    pushedTimestamps.add(timestamp);
  }
}
