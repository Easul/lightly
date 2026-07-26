import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'app_log_service.dart';
import '../features/remote_control/infrastructure/remote_control_platform_gateway.dart';

/// 屏幕帧类型
enum ScreenFrameType {
  config, // SPS/PPS 配置帧
  keyFrame, // IDR 关键帧
  deltaFrame, // P/B 参考帧
}

/// 屏幕帧数据
class ScreenFrame {
  final ScreenFrameType type;
  final Uint8List data;
  final int timestamp;

  ScreenFrame({
    required this.type,
    required this.data,
    required this.timestamp,
  });
}

/// 屏幕捕获管理器
///
/// 管理屏幕捕获的生命周期，处理 H.264 帧的接收和解码
class ScreenCaptureManager {
  ScreenCaptureManager({RemoteControlPlatformGateway? platformGateway})
    : _platformGateway =
          platformGateway ?? RemoteControlPlatformGateway.instance;

  final RemoteControlPlatformGateway _platformGateway;

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
      final result = await _platformGateway.startScreenCapture(
        fps: fps,
        bitrate: bitrate,
      );

      _isCapturing = result ?? false;
      if (_isCapturing) {
        recordRuntimeLog(
          'ScreenCapture',
          'Screen capture started',
          metadata: <String, Object?>{'fps': fps, 'bitrate': bitrate},
        );
      }
      return _isCapturing;
    } catch (e, stackTrace) {
      recordRuntimeLog(
        'ScreenCapture',
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
      await _platformGateway.stopScreenCapture();
      _isCapturing = false;
      _spsData = null;
      _ppsData = null;
      recordRuntimeLog('ScreenCapture', 'Screen capture stopped');
    } catch (e, stackTrace) {
      recordRuntimeLog(
        'ScreenCapture',
        'Failed to stop screen capture',
        error: e,
        stackTrace: stackTrace,
      );
    }
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

  /// 解析 H.264 NAL 单元
  ///
  /// 从裸 H.264 流中提取 SPS、PPS 和帧数据
  static List<Uint8List> parseNalUnits(Uint8List data) {
    final units = <Uint8List>[];
    int i = 0;

    while (i < data.length - 4) {
      // 查找起始码 0x00000001 或 0x000001
      if (data[i] == 0 && data[i + 1] == 0) {
        int startCodeLen;
        if (data[i + 2] == 0 && data[i + 3] == 1) {
          startCodeLen = 4;
        } else if (data[i + 2] == 1) {
          startCodeLen = 3;
        } else {
          i++;
          continue;
        }

        // 查找下一个起始码
        int j = i + startCodeLen;
        while (j < data.length - 3) {
          if (data[j] == 0 &&
              data[j + 1] == 0 &&
              (data[j + 2] == 1 ||
                  (data[j + 2] == 0 &&
                      j + 3 < data.length &&
                      data[j + 3] == 1))) {
            break;
          }
          j++;
        }

        final nalUnit = Uint8List.fromList(data.sublist(i + startCodeLen, j));
        units.add(nalUnit);
        i = j;
      } else {
        i++;
      }
    }

    return units;
  }

  /// 获取 NAL 单元类型
  static int getNalUnitType(Uint8List nalUnit) {
    if (nalUnit.isEmpty) return -1;
    return nalUnit[0] & 0x1F;
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
      await _platformGateway.requestKeyFrame();
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
      await _platformGateway.updateBitrate(bitrate);
    } catch (e) {
      developer.log(
        'Failed to update bitrate: $e',
        name: 'ScreenCapture',
        error: e,
      );
    }
  }

  void dispose() {
    stopCapture();
    _frameController.close();
  }
}
