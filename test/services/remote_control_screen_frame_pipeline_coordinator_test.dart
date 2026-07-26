import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/application/remote_control_screen_frame_pipeline_coordinator.dart';
import 'package:lightly/features/remote_control/domain/screen_frame.dart';

void main() {
  group('RemoteControlScreenFramePipelineCoordinator', () {
    test('buffers partial frame until payload is complete', () {
      final pipeline = RemoteControlScreenFramePipelineCoordinator();
      final partial = Uint8List.fromList(<int>[0x02, 0, 0, 0, 3, 1]);

      final first = pipeline.handleIncomingData(
        partial,
        awaitingRecoveryKeyFrame: false,
        latestFrameBatchThreshold: 3,
      );

      expect(first.framesToEmit, isEmpty);
      expect(first.remainingBufferLength, partial.length);
      expect(pipeline.bufferLength, partial.length);

      final second = pipeline.handleIncomingData(
        Uint8List.fromList(<int>[2, 3]),
        awaitingRecoveryKeyFrame: false,
        latestFrameBatchThreshold: 3,
      );

      expect(second.framesToEmit, hasLength(1));
      expect(second.framesToEmit.single.type, ScreenFrameType.keyFrame);
      expect(second.framesToEmit.single.data, <int>[1, 2, 3]);
      expect(second.remainingBufferLength, 0);
      expect(pipeline.bufferLength, 0);
    });

    test('tracks latest sps and pps config frames', () {
      final pipeline = RemoteControlScreenFramePipelineCoordinator();
      final sps = Uint8List.fromList(<int>[0, 0, 0, 1, 0x67, 1]);
      final pps = Uint8List.fromList(<int>[0, 0, 0, 1, 0x68, 2]);

      final result = pipeline.handleIncomingData(
        Uint8List.fromList(<int>[..._packet(0x01, sps), ..._packet(0x01, pps)]),
        awaitingRecoveryKeyFrame: false,
        latestFrameBatchThreshold: 3,
      );

      expect(result.framesToEmit, hasLength(2));
      expect(result.awaitingRecoveryKeyFrame, isTrue);
      expect(pipeline.latestSps, sps);
      expect(pipeline.latestPps, pps);
    });

    test('drops delta frames while awaiting a recovery key frame', () {
      final pipeline = RemoteControlScreenFramePipelineCoordinator();

      final result = pipeline.handleIncomingData(
        Uint8List.fromList(<int>[
          ..._packet(0x03, Uint8List.fromList(<int>[1])),
          ..._packet(0x03, Uint8List.fromList(<int>[2])),
        ]),
        awaitingRecoveryKeyFrame: true,
        latestFrameBatchThreshold: 3,
      );

      expect(result.parsedFrameCount, 2);
      expect(result.framesToEmit, isEmpty);
      expect(result.droppedFrameCount, 2);
    });

    test('keeps latest configs and key frame for large batches', () {
      final pipeline = RemoteControlScreenFramePipelineCoordinator();
      final config1 = Uint8List.fromList(<int>[0x67, 1]);
      final config2 = Uint8List.fromList(<int>[0x68, 2]);
      final keyFrame = Uint8List.fromList(<int>[9, 9]);

      final result = pipeline.handleIncomingData(
        Uint8List.fromList(<int>[
          ..._packet(0x03, Uint8List.fromList(<int>[1])),
          ..._packet(0x01, config1),
          ..._packet(0x01, config2),
          ..._packet(0x02, keyFrame),
          ..._packet(0x03, Uint8List.fromList(<int>[2])),
        ]),
        awaitingRecoveryKeyFrame: false,
        latestFrameBatchThreshold: 3,
      );

      expect(result.parsedFrameCount, 5);
      expect(result.framesToEmit, hasLength(3));
      expect(result.framesToEmit.map((frame) => frame.type), <ScreenFrameType>[
        ScreenFrameType.config,
        ScreenFrameType.config,
        ScreenFrameType.keyFrame,
      ]);
      expect(result.framesToEmit.last.data, keyFrame);
    });

    test('reset clears buffered data and cached config frames', () {
      final pipeline = RemoteControlScreenFramePipelineCoordinator();
      final sps = Uint8List.fromList(<int>[0x67, 1]);

      pipeline.handleIncomingData(
        Uint8List.fromList(_packet(0x01, sps)),
        awaitingRecoveryKeyFrame: false,
        latestFrameBatchThreshold: 3,
      );
      pipeline.handleIncomingData(
        Uint8List.fromList(<int>[0x02, 0, 0, 0, 4, 1]),
        awaitingRecoveryKeyFrame: false,
        latestFrameBatchThreshold: 3,
      );

      expect(pipeline.latestSps, isNotNull);
      expect(pipeline.bufferLength, greaterThan(0));

      pipeline.reset();

      expect(pipeline.latestSps, isNull);
      expect(pipeline.latestPps, isNull);
      expect(pipeline.bufferLength, 0);
    });
  });
}

List<int> _packet(int frameType, Uint8List payload) {
  final length = payload.length;
  return <int>[
    frameType,
    (length >> 24) & 0xff,
    (length >> 16) & 0xff,
    (length >> 8) & 0xff,
    length & 0xff,
    ...payload,
  ];
}
