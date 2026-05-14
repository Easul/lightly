import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:record/record.dart';

class AudioCaptureService {
  // AGC 配置
  static const double _defaultTargetLevel = -16.0; // 目标音量等级 dB
  static const double _minGain = 1.0;
  static const double _maxGain = 3.5;
  static const double _agcAttackRate = 0.15; // 增益攻击速率
  static const double _agcDecayRate = 0.05; // 增益衰减速率

  final AudioRecorder _recorder = AudioRecorder();

  final StreamController<Uint8List> _frameController =
      StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get frameStream => _frameController.stream;

  bool _isCapturing = false;
  bool get isCapturing => _isCapturing;

  int _sequence = 0;
  int get sequence => _sequence;
  int _sampleRate = 16000;
  int _channels = 1;
  final List<int> _pendingPcmBytes = [];

  // AGC 状态
  double _currentGain = 2.0; // 初始增益提升到 2.0x
  double _smoothedRms = -60.0; // 平滑 RMS 分贝贝数
  final List<double> _rmsHistory = []; // 历史 RMS 缓冲
  static const int _rmsWindowSize = 10; // RMS 窗口大小

  double get currentGain => _currentGain;

  int get _frameBytes => (_sampleRate * _channels * 2 * 20) ~/ 1000;

  Future<void> initialize({int sampleRate = 16000, int channels = 1}) async {
    _sampleRate = sampleRate;
    _channels = channels;

    developer.log(
      'AudioCaptureService initialized: $_sampleRate Hz, $_channels ch',
      name: 'AudioCapture',
    );
  }

  Future<bool> start() async {
    if (_isCapturing) return true;

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        developer.log(
          'Audio recording permission denied',
          name: 'AudioCapture',
        );
        return false;
      }

      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: _channels,
          androidConfig: const AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
            audioManagerMode: AudioManagerMode.modeInCommunication,
            speakerphone: true,
          ),
          noiseSuppress: true,
          echoCancel: true,
        ),
      );

      stream.listen(
        _handleAudioData,
        onError: _handleError,
        onDone: _handleDone,
      );

      _isCapturing = true;
      _sequence = 0;
      _pendingPcmBytes.clear();
      developer.log('Audio capture started', name: 'AudioCapture');
      return true;
    } catch (e) {
      developer.log(
        'Failed to start audio capture: $e',
        name: 'AudioCapture',
        error: e,
      );
      return false;
    }
  }

  void _handleAudioData(Uint8List pcmData) {
    try {
      _pendingPcmBytes.addAll(pcmData);
      while (_pendingPcmBytes.length >= _frameBytes) {
        final frame = Uint8List.fromList(
          _pendingPcmBytes.sublist(0, _frameBytes),
        );
        _pendingPcmBytes.removeRange(0, _frameBytes);
        _sequence++;
        _frameController.add(_applyAGCGain(frame));
      }
    } catch (e) {
      developer.log(
        'Error processing audio: $e',
        name: 'AudioCapture',
        error: e,
      );
    }
  }

  /// 计算 PCM 数据的 RMS 分贝贝数 (dB)
  double _calculateRms(Uint8List pcmData) {
    if (pcmData.length < 2) return -60.0;
    double sumSquares = 0.0;
    final samples = ByteData.sublistView(pcmData);
    int sampleCount = 0;

    for (var offset = 0; offset + 1 < pcmData.length; offset += 2) {
      final sample = samples.getInt16(offset, Endian.little);
      sumSquares += sample * sample;
      sampleCount++;
    }

    if (sampleCount == 0) return -60.0;
    final rms = math.sqrt(sumSquares / sampleCount);
    if (rms < 1) return -60.0;
    return 20.0 * math.log(rms / 32768.0) / math.log(10);
  }

  /// 更新 AGC 增益
  void _updateAGC(double currentRms) {
    // 穹滑 RMS 历史
    _rmsHistory.add(currentRms);
    if (_rmsHistory.length > _rmsWindowSize) {
      _rmsHistory.removeAt(0);
    }

    // 计算平均 RMS
    final avgRms = _rmsHistory.reduce((a, b) => a + b) / _rmsHistory.length;

    // 更新平滑 RMS (加权移动平均)
    _smoothedRms = _smoothedRms * 0.7 + avgRms * 0.3;

    // 计算目标增益
    final targetGain = _calculateTargetGain(_smoothedRms);

    // 平滑增益调整 (攻击/衰减)
    if (targetGain > _currentGain) {
      // 音量低, 快速提升增益
      _currentGain =
          _currentGain + (targetGain - _currentGain) * _agcAttackRate;
    } else {
      // 音量高, 慢慢降低增益 (防止裁剪)
      _currentGain = _currentGain + (targetGain - _currentGain) * _agcDecayRate;
    }

    // 限制增益范围
    _currentGain = _currentGain.clamp(_minGain, _maxGain);
  }

  /// 计算目标增益
  double _calculateTargetGain(double inputLevelDb) {
    // 如果输入太小, 不增益 (防止噪声放大)
    if (inputLevelDb < -50) return 1.0;
    // 如果输入已经很高, 不增益
    if (inputLevelDb > _defaultTargetLevel) return 1.0;
    // 计算需要的增益使输出到达目标等级
    final gainDb = _defaultTargetLevel - inputLevelDb;
    return math.pow(10, gainDb / 20.0).toDouble();
  }

  /// 应用 AGC 增益
  Uint8List _applyAGCGain(Uint8List pcmData) {
    // 计算当前音量并更新 AGC
    final currentRms = _calculateRms(pcmData);
    _updateAGC(currentRms);

    // 应用增益
    final boosted = Uint8List.fromList(pcmData);
    final samples = ByteData.sublistView(boosted);
    for (var offset = 0; offset + 1 < boosted.length; offset += 2) {
      final sample = samples.getInt16(offset, Endian.little);
      final amplified = (sample * _currentGain).round();
      final clamped = amplified.clamp(-32768, 32767);
      samples.setInt16(offset, clamped, Endian.little);
    }

    // 定期记录 AGC 状态 (调试)
    if (_sequence % 100 == 0) {
      developer.log(
        'AGC: input=${currentRms.toStringAsFixed(1)}dB, gain=${_currentGain.toStringAsFixed(2)}x, output=${(currentRms + 20 * math.log(_currentGain) / math.log(10)).toStringAsFixed(1)}dB',
        name: 'AudioCapture',
      );
    }

    return boosted;
  }

  void _handleError(dynamic error) {
    developer.log('Audio capture error: $error', name: 'AudioCapture');
  }

  void _handleDone() {
    developer.log('Audio capture stream done', name: 'AudioCapture');
    _isCapturing = false;
    _pendingPcmBytes.clear();
  }

  Future<void> stop() async {
    if (!_isCapturing) return;

    try {
      await _recorder.stop();
      _isCapturing = false;
      _sequence = 0;
      _pendingPcmBytes.clear();
      developer.log('Audio capture stopped', name: 'AudioCapture');
    } catch (e) {
      developer.log(
        'Failed to stop audio capture: $e',
        name: 'AudioCapture',
        error: e,
      );
    }
  }

  void dispose() {
    stop();
    _frameController.close();
  }
}
