import 'dart:typed_data';

import 'screen_capture_manager.dart';

class ScreenPipelineParseResult {
  final List<ScreenFrame> parsedFrames;
  final Uint8List? latestSps;
  final Uint8List? latestPps;
  final bool awaitingRecoveryKeyFrame;

  const ScreenPipelineParseResult({
    required this.parsedFrames,
    required this.latestSps,
    required this.latestPps,
    required this.awaitingRecoveryKeyFrame,
  });
}

class RemoteControlScreenPipelineHelper {
  const RemoteControlScreenPipelineHelper();

  ScreenPipelineParseResult parseScreenDataBuffer({
    required List<int> screenDataBuffer,
    required bool awaitingRecoveryKeyFrame,
  }) {
    final parsedFrames = <ScreenFrame>[];
    Uint8List? latestSps;
    Uint8List? latestPps;
    var nextAwaitingRecoveryKeyFrame = awaitingRecoveryKeyFrame;

    while (screenDataBuffer.length >= 5) {
      final frameType = screenDataBuffer[0];
      final frameLength =
          (screenDataBuffer[1] << 24) |
          (screenDataBuffer[2] << 16) |
          (screenDataBuffer[3] << 8) |
          screenDataBuffer[4];

      if (screenDataBuffer.length < 5 + frameLength) {
        break;
      }

      final frameData = Uint8List.fromList(
        screenDataBuffer.sublist(5, 5 + frameLength),
      );
      screenDataBuffer.removeRange(0, 5 + frameLength);

      ScreenFrameType type;
      switch (frameType) {
        case 0x01:
          type = ScreenFrameType.config;
          final nalType = extractNalType(frameData);
          if (nalType == 7) {
            latestSps = frameData;
          } else if (nalType == 8) {
            latestPps = frameData;
          }
          nextAwaitingRecoveryKeyFrame = true;
          break;
        case 0x02:
          type = ScreenFrameType.keyFrame;
          nextAwaitingRecoveryKeyFrame = false;
          break;
        case 0x03:
        default:
          type = ScreenFrameType.deltaFrame;
          break;
      }

      parsedFrames.add(
        ScreenFrame(
          type: type,
          data: frameData,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    return ScreenPipelineParseResult(
      parsedFrames: parsedFrames,
      latestSps: latestSps,
      latestPps: latestPps,
      awaitingRecoveryKeyFrame: nextAwaitingRecoveryKeyFrame,
    );
  }

  List<ScreenFrame> coalesceLatestScreenFrames(
    List<ScreenFrame> frames, {
    required int latestFrameBatchThreshold,
    required bool awaitingRecoveryKeyFrame,
  }) {
    if (frames.length < latestFrameBatchThreshold) {
      if (awaitingRecoveryKeyFrame) {
        return frames
            .where((frame) => frame.type != ScreenFrameType.deltaFrame)
            .toList();
      }
      return frames;
    }

    final latestConfigs = <ScreenFrame>[];
    ScreenFrame? latestKeyFrame;

    for (final frame in frames) {
      switch (frame.type) {
        case ScreenFrameType.config:
          latestConfigs.add(frame);
          if (latestConfigs.length > 2) {
            latestConfigs.removeRange(0, latestConfigs.length - 2);
          }
          latestKeyFrame = null;
          break;
        case ScreenFrameType.keyFrame:
          latestKeyFrame = frame;
          break;
        case ScreenFrameType.deltaFrame:
          break;
      }
    }

    final coalesced = <ScreenFrame>[];
    coalesced.addAll(latestConfigs);
    if (latestKeyFrame != null) {
      coalesced.add(latestKeyFrame);
      return coalesced;
    }
    if (awaitingRecoveryKeyFrame) {
      return coalesced;
    }
    return coalesced.isEmpty ? [frames.last] : coalesced;
  }

  int extractNalType(Uint8List data) {
    if (data.isEmpty) return -1;
    var offset = 0;
    if (data.length >= 4 && data[0] == 0 && data[1] == 0) {
      if (data[2] == 1) {
        offset = 3;
      } else if (data[2] == 0 && data[3] == 1) {
        offset = 4;
      }
    }
    if (offset >= data.length) return -1;
    return data[offset] & 0x1F;
  }
}
