import 'dart:typed_data';

import '../domain/screen_frame.dart';
import 'remote_control_screen_pipeline_helper.dart';

class RemoteControlScreenFramePipelineResult {
  const RemoteControlScreenFramePipelineResult({
    required this.parsedFrameCount,
    required this.framesToEmit,
    required this.awaitingRecoveryKeyFrame,
    required this.remainingBufferLength,
  });

  final int parsedFrameCount;
  final List<ScreenFrame> framesToEmit;
  final bool awaitingRecoveryKeyFrame;
  final int remainingBufferLength;

  int get droppedFrameCount => parsedFrameCount - framesToEmit.length;
}

class RemoteControlScreenFramePipelineCoordinator {
  RemoteControlScreenFramePipelineCoordinator({
    RemoteControlScreenPipelineHelper helper =
        const RemoteControlScreenPipelineHelper(),
  }) : _helper = helper;

  final RemoteControlScreenPipelineHelper _helper;
  final List<int> _screenDataBuffer = [];
  Uint8List? _latestSps;
  Uint8List? _latestPps;

  int get bufferLength => _screenDataBuffer.length;
  Uint8List? get latestSps => _latestSps;
  Uint8List? get latestPps => _latestPps;

  RemoteControlScreenFramePipelineResult handleIncomingData(
    Uint8List data, {
    required bool awaitingRecoveryKeyFrame,
    required int latestFrameBatchThreshold,
  }) {
    _screenDataBuffer.addAll(data);

    final parseResult = _helper.parseScreenDataBuffer(
      screenDataBuffer: _screenDataBuffer,
      awaitingRecoveryKeyFrame: awaitingRecoveryKeyFrame,
    );
    if (parseResult.latestSps != null) {
      _latestSps = parseResult.latestSps;
    }
    if (parseResult.latestPps != null) {
      _latestPps = parseResult.latestPps;
    }

    final framesToEmit = _helper.coalesceLatestScreenFrames(
      parseResult.parsedFrames,
      latestFrameBatchThreshold: latestFrameBatchThreshold,
      awaitingRecoveryKeyFrame: parseResult.awaitingRecoveryKeyFrame,
    );

    return RemoteControlScreenFramePipelineResult(
      parsedFrameCount: parseResult.parsedFrames.length,
      framesToEmit: framesToEmit,
      awaitingRecoveryKeyFrame: parseResult.awaitingRecoveryKeyFrame,
      remainingBufferLength: _screenDataBuffer.length,
    );
  }

  void reset() {
    _screenDataBuffer.clear();
    _latestSps = null;
    _latestPps = null;
  }
}
