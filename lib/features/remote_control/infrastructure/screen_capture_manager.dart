import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../../../core/logging/runtime_logger.dart';
import '../domain/remote_control_runtime.dart';
import '../domain/screen_frame.dart';

/// 屏幕捕获管理器
///
/// 管理屏幕捕获的生命周期，处理 H.264 帧的接收和解码
class ScreenCaptureManager {
  ScreenCaptureManager({
    required RemoteControlCapturePlatformRuntime platformRuntime,
    RuntimeLogger runtimeLogger = const NoopRuntimeLogger(),
  }) : _platformRuntime = platformRuntime,
       _runtimeLogger = runtimeLogger;

  final RemoteControlCapturePlatformRuntime _platformRuntime;
  RuntimeLogger _runtimeLogger;

  final StreamController<ScreenFrame> _frameController =
      StreamController<ScreenFrame>.broadcast();

  Stream<ScreenFrame> get frameStream => _frameController.stream;

  bool _isCapturing = false;
  bool get isCapturing => _isCapturing;

  int _frameCount = 0;
  int get frameCount => _frameCount;

  Uint8List? _spsData;
  Uint8List? _ppsData;

  Uint8List? get spsData => _spsData;
  Uint8List? get ppsData => _ppsData;

  /// 开始屏幕捕获（被控端调用）
  Future<bool> startCapture({int fps = 15, int bitrate = 2000000}) async {
    if (_isCapturing) return true;

    try {
      final result = await _platformRuntime.startScreenCapture(
        fps: fps,
        bitrate: bitrate,
      );

      _isCapturing = result ?? false;
      if (_isCapturing) {
        _recordRuntimeLog(
          'Screen capture started',
          metadata: <String, Object?>{'fps': fps, 'bitrate': bitrate},
        );
      }
      return _isCapturing;
    } catch (e, stackTrace) {
      _recordRuntimeLog(
        'Failed to start screen capture',
        error: e,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'fps': fps, 'bitrate': bitrate},
      );
      return false;
    }
  }

  /// 停止屏幕捕获
  Future<void> stopCapture() async {
    if (!_isCapturing) return;

    try {
      await _platformRuntime.stopScreenCapture();
      _isCapturing = false;
      _spsData = null;
      _ppsData = null;
      _recordRuntimeLog('Screen capture stopped');
    } catch (e, stackTrace) {
      _recordRuntimeLog(
        'Failed to stop screen capture',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void configureRuntimeLogger(RuntimeLogger runtimeLogger) {
    if (_isCapturing) {
      throw StateError('Cannot replace logger while screen capture is active');
    }
    _runtimeLogger = runtimeLogger;
  }

  /// 处理从原生层接收的屏幕帧
  ///
  /// 由 MethodChannel 回调调用
  void handleNativeFrame(Uint8List data, bool isKeyFrame) {
    _frameCount++;

    final frame = ScreenFrame(
      type: isKeyFrame ? ScreenFrameType.keyFrame : ScreenFrameType.deltaFrame,
      data: data,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _frameController.add(frame);
  }

  /// 处理 H.264 配置帧（SPS/PPS）
  void handleConfigFrame(Uint8List sps, Uint8List pps) {
    _spsData = sps;
    _ppsData = pps;

    final frame = ScreenFrame(
      type: ScreenFrameType.config,
      data: _buildConfigData(sps, pps),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _frameController.add(frame);
    developer.log(
      'Config frame received: SPS=${sps.length} PPS=${pps.length}',
      name: 'ScreenCapture',
    );
  }

  /// 构建配置数据
  Uint8List _buildConfigData(Uint8List sps, Uint8List pps) {
    // AVCC 格式：4字节长度前缀 + NAL单元
    final builder = BytesBuilder();

    // SPS
    builder.add(_intToBytes(sps.length, 4));
    builder.add(sps);

    // PPS
    builder.add(_intToBytes(pps.length, 4));
    builder.add(pps);

    return builder.toBytes();
  }

  /// 将整数转换为指定长度的字节
  Uint8List _intToBytes(int value, int length) {
    final bytes = Uint8List(length);
    for (int i = length - 1; i >= 0; i--) {
      bytes[i] = value & 0xFF;
      value >>= 8;
    }
    return bytes;
  }

  /// 请求关键帧
  Future<void> requestKeyFrame() async {
    try {
      await _platformRuntime.requestKeyFrame();
    } catch (e) {
      developer.log(
        'Failed to request key frame: $e',
        name: 'ScreenCapture',
        error: e,
      );
    }
  }

  /// 更新码率
  Future<void> updateBitrate(int bitrate) async {
    try {
      await _platformRuntime.updateBitrate(bitrate);
    } catch (e) {
      developer.log(
        'Failed to update bitrate: $e',
        name: 'ScreenCapture',
        error: e,
      );
    }
  }

  void _recordRuntimeLog(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) {
    developer.log(
      message,
      name: 'ScreenCapture',
      error: error,
      stackTrace: stackTrace,
    );
    unawaited(
      _runtimeLogger
          .log(
            '[ScreenCapture] $message',
            error: error,
            stackTrace: stackTrace,
            metadata: metadata,
          )
          .catchError((_) {}),
    );
  }

  void dispose() {
    stopCapture();
    _frameController.close();
  }
}
