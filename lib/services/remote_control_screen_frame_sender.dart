import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../features/remote_control/domain/screen_frame.dart';

class RemoteControlScreenFrameSender {
  RemoteControlScreenFrameSender({this.log});

  final void Function(String message)? log;

  IOSink? _sink;
  ScreenFrame? _pendingKeyFrame;
  ScreenFrame? _pendingDeltaFrame;
  bool _isSending = false;
  int _droppedStaleFrameCount = 0;

  int get droppedStaleFrameCount => _droppedStaleFrameCount;
  bool get isSending => _isSending;
  bool get hasPendingFrame =>
      _pendingKeyFrame != null || _pendingDeltaFrame != null;

  void attach(Socket socket) {
    attachSink(socket);
  }

  void attachSink(IOSink sink) {
    _sink = sink;
    _pendingKeyFrame = null;
    _pendingDeltaFrame = null;
    _isSending = false;
    _droppedStaleFrameCount = 0;
  }

  void detach(Socket socket) {
    if (!identical(_sink, socket)) {
      return;
    }
    reset();
  }

  void reset() {
    _sink = null;
    _pendingKeyFrame = null;
    _pendingDeltaFrame = null;
    _isSending = false;
    _droppedStaleFrameCount = 0;
  }

  void sendConfig(Uint8List sps, Uint8List pps) {
    final sink = _sink;
    if (sink == null) return;
    sink.add(_encodeFrame(0x01, sps));
    sink.add(_encodeFrame(0x01, pps));
  }

  void enqueueFrame(ScreenFrame frame) {
    if (_sink == null) return;

    switch (frame.type) {
      case ScreenFrameType.config:
        _sink!.add(_encodeFrame(0x01, frame.data));
        return;
      case ScreenFrameType.keyFrame:
        if (_pendingKeyFrame != null) {
          _droppedStaleFrameCount += 1;
        }
        _pendingKeyFrame = frame;
        if (_pendingDeltaFrame != null) {
          _droppedStaleFrameCount += 1;
          _pendingDeltaFrame = null;
        }
        break;
      case ScreenFrameType.deltaFrame:
        if (_pendingDeltaFrame != null) {
          _droppedStaleFrameCount += 1;
        }
        _pendingDeltaFrame = frame;
        break;
    }

    if (!_isSending) {
      unawaited(_pump());
    }
  }

  Future<void> _pump() async {
    final sink = _sink;
    if (sink == null || _isSending) {
      return;
    }

    _isSending = true;
    try {
      while (identical(_sink, sink)) {
        final frame = _takeNextFrame();
        if (frame == null) {
          return;
        }
        sink.add(_encodeFrame(_frameTypeByte(frame), frame.data));
        await sink.flush();
        if (_droppedStaleFrameCount > 0) {
          log?.call(
            'Dropped stale outgoing screen frames: count=$_droppedStaleFrameCount',
          );
          _droppedStaleFrameCount = 0;
        }
      }
    } finally {
      _isSending = false;
      if (identical(_sink, sink) && hasPendingFrame) {
        unawaited(_pump());
      }
    }
  }

  ScreenFrame? _takeNextFrame() {
    final keyFrame = _pendingKeyFrame;
    if (keyFrame != null) {
      _pendingKeyFrame = null;
      return keyFrame;
    }
    final deltaFrame = _pendingDeltaFrame;
    _pendingDeltaFrame = null;
    return deltaFrame;
  }

  int _frameTypeByte(ScreenFrame frame) {
    return switch (frame.type) {
      ScreenFrameType.config => 0x01,
      ScreenFrameType.keyFrame => 0x02,
      ScreenFrameType.deltaFrame => 0x03,
    };
  }

  Uint8List _encodeFrame(int frameType, Uint8List data) {
    final bytes = Uint8List(5 + data.length);
    final view = ByteData.view(bytes.buffer);
    view.setUint8(0, frameType);
    view.setUint32(1, data.length, Endian.big);
    bytes.setRange(5, bytes.length, data);
    return bytes;
  }
}
