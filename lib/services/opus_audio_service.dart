import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:opus_dart/opus_dart.dart';

/// Opus 音频编码解码服务
///
/// 将 PCM 音频编码为 Opus (大幅减少带宽)
/// 从 Opus 解码为 PCM (用于播放)
class OpusAudioService {
  static const int _sampleRate = 16000;
  static const int _channels = 1;
  static const int _frameDurationMs = 20;
  // Opus 20ms @ 16kHz 单声道 约 60 bytes 带宽 ~24kbps
  static const int _maxEncodedSize = 80;

  SimpleOpusEncoder? _encoder;
  SimpleOpusDecoder? _decoder;

  bool _isInitialized = false;
  int _encodedFrameCount = 0;
  int _decodedFrameCount = 0;
  int _totalEncodedBytes = 0;
  int _totalDecodedBytes = 0;

  /// 初始化 Opus 编码器和解码器
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _encoder = SimpleOpusEncoder(
        sampleRate: _sampleRate,
        channels: _channels,
        application: Application.voip,
      );

      _decoder = SimpleOpusDecoder(
        sampleRate: _sampleRate,
        channels: _channels,
      );

      _isInitialized = true;
      developer.log(
        'Opus initialized: sampleRate=$_sampleRate, maxOutputSizeBytes=$_maxEncodedSize',
        name: 'OpusAudio',
      );
    } catch (e) {
      developer.log(
        'Failed to initialize Opus: $e',
        name: 'OpusAudio',
        error: e,
      );
      rethrow;
    }
  }

  /// 编码 PCM 数据为 Opus
  ///
  /// [pcmData] 应为 16-bit PCM 格式 (Uint8List, little-endian)
  /// 返回 Opus 编码后的数据 (10:1 压缩比例)
  Uint8List? encodeFrame(Uint8List pcmData) {
    if (!_isInitialized || _encoder == null) {
      return null;
    }

    try {
      final frameSize = (_sampleRate * _frameDurationMs ~/ 1000); // 320 samples
      final expectedBytes = frameSize * _channels * 2; // 640 bytes

      // 确保数据长度正确
      Uint8List inputData = pcmData;
      if (pcmData.length < expectedBytes) {
        // 填充静音到完整帧
        final padded = Uint8List(expectedBytes);
        padded.setAll(0, pcmData);
        inputData = padded;
      } else if (pcmData.length > expectedBytes) {
        inputData = Uint8List.sublistView(pcmData, 0, expectedBytes);
      }

      // 将 Uint8List 转换为 Int16List (little-endian)
      final int16Data = Int16List(frameSize);
      final byteData = ByteData.sublistView(inputData);
      for (var i = 0; i < frameSize; i++) {
        int16Data[i] = byteData.getInt16(i * 2, Endian.little);
      }

      final encoded = _encoder!.encode(
        input: int16Data,
        maxOutputSizeBytes: _maxEncodedSize,
      );

      _encodedFrameCount++;
      _totalEncodedBytes += encoded.length;

      if (_encodedFrameCount % 100 == 0) {
        final avgSize = _totalEncodedBytes / _encodedFrameCount;
        developer.log(
          'Opus encode stats: avg=${avgSize.toStringAsFixed(1)} bytes/frame, '
          'compression=${(expectedBytes / avgSize).toStringAsFixed(1)}x',
          name: 'OpusAudio',
        );
      }

      return encoded;
    } catch (e) {
      developer.log('Opus encode error: $e', name: 'OpusAudio', error: e);
      return null;
    }
  }

  /// 解码 Opus 数据为 PCM
  ///
  /// [opusData] Opus 编码数据
  /// 返回 16-bit PCM 格式的数据 (Uint8List, little-endian)
  Uint8List? decodeFrame(Uint8List opusData) {
    if (!_isInitialized || _decoder == null) {
      return null;
    }

    try {
      // 解码为 Int16List (使用 SimpleOpusDecoder 的 decode 方法)
      final decoded = _decoder!.decode(input: opusData);

      // 转换为 Uint8List (little-endian)
      final output = Uint8List(decoded.length * 2);
      final byteData = ByteData.sublistView(output);
      for (var i = 0; i < decoded.length; i++) {
        byteData.setInt16(i * 2, decoded[i], Endian.little);
      }

      _decodedFrameCount++;
      _totalDecodedBytes += opusData.length;

      return output;
    } catch (e) {
      developer.log('Opus decode error: $e', name: 'OpusAudio', error: e);
      return null;
    }
  }

  /// 获取统计信息
  Map<String, dynamic> getStats() {
    return {
      'encodedFrames': _encodedFrameCount,
      'decodedFrames': _decodedFrameCount,
      'totalEncodedBytes': _totalEncodedBytes,
      'totalDecodedBytes': _totalDecodedBytes,
      'avgEncodedSize': _encodedFrameCount > 0
          ? (_totalEncodedBytes / _encodedFrameCount).toStringAsFixed(1)
          : '0',
    };
  }

  void dispose() {
    _encoder?.destroy();
    _decoder?.destroy();
    _encoder = null;
    _decoder = null;
    _isInitialized = false;
  }
}
