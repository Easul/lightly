import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';

class AudioFrame {
  final Uint8List data;
  final int sequence;
  final int timestamp;

  AudioFrame({
    required this.data,
    required this.sequence,
    required this.timestamp,
  });
}

class JitterBuffer {
  static const int _timestampModulo = 0x100000000;
  static const int _sequenceModulo = 0x10000;
  // 固定配置
  final int _frameIntervalMs;
  static const int _minTargetDelayMs = 20; // 最小目标延迟 (局域网)
  static const int _maxTargetDelayMs = 180; // 最大目标延迟 (差网络)
  static const int _minBufferSize = 3; // 最小缓冲区大小
  static const int _maxBufferSize = 20; // 最大缓冲区大小

  // 动态状态
  final List<AudioFrame> _buffer = [];
  final List<int> _networkDelayHistory = []; // 网络延迟历史 (ms)
  int _currentTargetDelayMs = 60; // 当前目标延迟
  int _currentMaxSize = 12; // 当前缓冲区大小
  int _nextSequence = 0;
  Timer? _playbackTimer;

  final StreamController<Uint8List> _outputController =
      StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get outputStream => _outputController.stream;

  bool _isPlaying = false;
  int _dropCount = 0;
  int _lateCount = 0;
  int _packetLossCount = 0;
  int _totalReceived = 0;
  int _lastReceivedSequence = -1;

  // 调试信息
  DateTime _lastStatsTime = DateTime.now();
  double _avgLatencyMs = 0;
  double _jitterMs = 0;

  JitterBuffer({int frameIntervalMs = 20}) : _frameIntervalMs = frameIntervalMs;

  /// 计算当前网络延迟
  int _calculateNetworkDelay(AudioFrame frame) {
    final arrivalTime = DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF;
    final senderTime = frame.timestamp;
    final rawDelay = arrivalTime >= senderTime
        ? arrivalTime - senderTime
        : arrivalTime + _timestampModulo - senderTime;
    final networkDelay = rawDelay.clamp(0, 500);
    return networkDelay;
  }

  int _sequenceGap(int previous, int current) {
    if (previous < 0) {
      return 0;
    }
    final delta = current >= previous
        ? current - previous
        : current + _sequenceModulo - previous;
    return delta > 0 ? delta - 1 : 0;
  }

  /// 更新延迟统计和自适应缓冲参数
  void _updateAdaptiveBuffer(int networkDelayMs) {
    // 添加到历史
    _networkDelayHistory.add(networkDelayMs);
    if (_networkDelayHistory.length > 20) {
      _networkDelayHistory.removeAt(0);
    }

    if (_networkDelayHistory.length < 5) return;

    // 计算统计量
    final delays = List<int>.from(_networkDelayHistory)..sort();
    final medianDelay = delays[delays.length ~/ 2];
    final percentile90 = delays[(delays.length * 0.9).floor()];
    final jitter = percentile90 - medianDelay;

    _avgLatencyMs = medianDelay.toDouble();
    _jitterMs = jitter.toDouble();

    // 自适应目标延迟 = 中位数延迟 + 1.5 * 抖动 + 基础处理延迟
    final targetDelay = (medianDelay + 1.5 * jitter + 10).round();
    _currentTargetDelayMs = targetDelay.clamp(
      _minTargetDelayMs,
      _maxTargetDelayMs,
    );

    // 根据目标延迟计算缓冲区大小
    // 缓冲区大小应该容纳至少3个周期的数据
    final idealBufferSize =
        (_currentTargetDelayMs / _frameIntervalMs).ceil() + 2;
    _currentMaxSize = idealBufferSize.clamp(_minBufferSize, _maxBufferSize);

    // 每5秒打印一次调试信息
    final now = DateTime.now();
    if (now.difference(_lastStatsTime).inSeconds >= 5) {
      _lastStatsTime = now;
      developer.log(
        'JitterBuffer: avg=${_avgLatencyMs.toStringAsFixed(1)}ms, '
        'jitter=${_jitterMs.toStringAsFixed(1)}ms, '
        'targetDelay=${_currentTargetDelayMs}ms, '
        'bufferSize=$_currentMaxSize, '
        'packets=$_totalReceived, drops=$_dropCount, loss=${(_packetLossCount / (_totalReceived + _packetLossCount).clamp(1, 1 << 30) * 100).toStringAsFixed(1)}%',
        name: 'JitterBuffer',
      );
    }
  }

  void addFrame(AudioFrame frame) {
    _totalReceived++;

    // 计算网络延迟并更新自适应参数
    final networkDelay = _calculateNetworkDelay(frame);
    _updateAdaptiveBuffer(networkDelay);

    // 检查序列号跳跃 (检测丢包)
    final lossGap = _sequenceGap(_lastReceivedSequence, frame.sequence);
    if (lossGap > 0) {
      _packetLossCount += lossGap;
    }
    _lastReceivedSequence = frame.sequence;

    // 序列号去重
    final existingIndex = _buffer.indexWhere(
      (f) => f.sequence == frame.sequence,
    );
    if (existingIndex >= 0) {
      _buffer[existingIndex] = frame;
      return;
    }

    // 缓冲区管理
    if (_buffer.length >= _currentMaxSize) {
      // 优先删除旧的 delta frame, 保留 key frame
      final oldestIndex = _buffer.indexWhere((f) => f is! KeyAudioFrame);
      if (oldestIndex >= 0) {
        _buffer.removeAt(oldestIndex);
      } else {
        _buffer.removeAt(0);
      }
      _dropCount++;
    }

    _buffer.add(frame);
    _buffer.sort((a, b) => a.sequence.compareTo(b.sequence));

    // 检查是否需要等待更多数据
    if (!_isPlaying) {
      // 根据当前目标延迟决定起播阈值
      final requiredFrames = (_currentTargetDelayMs / _frameIntervalMs).ceil();
      if (_buffer.length >= requiredFrames.clamp(2, 6)) {
        _startPlayback();
      }
    }
  }

  void _startPlayback() {
    _isPlaying = true;
    _nextSequence = _buffer.first.sequence;

    // 使用固定间隔播放, 但根据延迟动态调整实际缓冲大小
    _playbackTimer = Timer.periodic(
      Duration(milliseconds: _frameIntervalMs),
      (_) => _playNextFrame(),
    );
  }

  void _playNextFrame() {
    if (_buffer.isEmpty) {
      // 缓冲区耗尽, 停止播放等待重新填充
      _stopPlayback();
      return;
    }

    final frame = _buffer.first;

    // 处理乱序包 (比期望序列号小 = 迟到)
    if (frame.sequence < _nextSequence) {
      final backwardGap = _nextSequence - frame.sequence;
      if (backwardGap >= _sequenceModulo ~/ 2) {
        _nextSequence = frame.sequence;
      } else {
        _buffer.removeAt(0);
        _lateCount++;
        return;
      }
    }

    // 处理正常序列
    if (frame.sequence == _nextSequence) {
      _buffer.removeAt(0);
      _outputController.add(frame.data);
      _nextSequence++;
    } else {
      // 序列号缺失, 插入静音 (简单的基于前后帧的插值可以后续实现)
      _outputController.add(Uint8List(frame.data.length));
      _nextSequence++;
    }
  }

  void _stopPlayback() {
    _isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
  }

  void clear() {
    _buffer.clear();
    _networkDelayHistory.clear();
    _stopPlayback();
    _nextSequence = 0;
    _dropCount = 0;
    _lateCount = 0;
    _packetLossCount = 0;
    _totalReceived = 0;
    _lastReceivedSequence = -1;
    _currentTargetDelayMs = 60;
    _currentMaxSize = 12;
  }

  void dispose() {
    clear();
    _outputController.close();
  }

  // 暴露统计信息供监控
  Map<String, dynamic> get stats => {
    'avgLatencyMs': _avgLatencyMs,
    'jitterMs': _jitterMs,
    'targetDelayMs': _currentTargetDelayMs,
    'bufferSize': _buffer.length,
    'maxBufferSize': _currentMaxSize,
    'dropCount': _dropCount,
    'lateCount': _lateCount,
    'packetLossRate': _totalReceived > 0
        ? _packetLossCount / (_totalReceived + _packetLossCount)
        : 0.0,
  };
}

// 占位符, 用于区分 key frame (如果未来需要支持)
class KeyAudioFrame extends AudioFrame {
  KeyAudioFrame({
    required super.data,
    required super.sequence,
    required super.timestamp,
  });
}

class AudioPlaybackService {
  static const MethodChannel _channel = MethodChannel('remote_control');

  JitterBuffer? _jitterBuffer;
  StreamSubscription<Uint8List>? _playbackSubscription;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Future<void> initialize({int sampleRate = 16000, int channels = 1}) async {
    _jitterBuffer = JitterBuffer();

    try {
      await _channel.invokeMethod('initAudioPlayer', {
        'sampleRate': sampleRate,
        'channels': channels,
      });
      developer.log('AudioPlaybackService initialized', name: 'AudioPlayback');
    } catch (e) {
      developer.log(
        'Failed to initialize audio player: $e',
        name: 'AudioPlayback',
        error: e,
      );
      rethrow;
    }
  }

  void feedFrame(Uint8List data, int sequence, int timestamp) {
    if (_jitterBuffer == null) return;

    final frame = AudioFrame(
      data: data,
      sequence: sequence,
      timestamp: timestamp,
    );

    _jitterBuffer!.addFrame(frame);
  }

  Future<void> start() async {
    if (_isPlaying || _jitterBuffer == null) return;

    try {
      await _channel.invokeMethod('startAudioPlayer');

      _playbackSubscription = _jitterBuffer!.outputStream.listen(
        _playAudioData,
        onError: _handleError,
        onDone: _handleDone,
      );

      _isPlaying = true;
      developer.log('Audio playback started', name: 'AudioPlayback');
    } catch (e) {
      developer.log(
        'Failed to start audio playback: $e',
        name: 'AudioPlayback',
        error: e,
      );
    }
  }

  void _playAudioData(Uint8List pcmData) {
    try {
      _channel.invokeMethod('playAudio', {'data': pcmData});
    } catch (e) {
      developer.log('Error playing audio: $e', name: 'AudioPlayback', error: e);
    }
  }

  void _handleError(dynamic error) {
    developer.log('Audio playback error: $error', name: 'AudioPlayback');
  }

  void _handleDone() {
    developer.log('Audio playback stream done', name: 'AudioPlayback');
    _isPlaying = false;
  }

  Future<void> stop() async {
    if (!_isPlaying) return;

    try {
      _playbackSubscription?.cancel();
      _playbackSubscription = null;
      _jitterBuffer?.clear();
      _isPlaying = false;

      await _channel.invokeMethod('stopAudioPlayer');
      developer.log('Audio playback stopped', name: 'AudioPlayback');
    } catch (e) {
      developer.log(
        'Failed to stop audio playback: $e',
        name: 'AudioPlayback',
        error: e,
      );
    }
  }

  void dispose() {
    stop();
    _jitterBuffer?.dispose();
    _jitterBuffer = null;
    try {
      _channel.invokeMethod('releaseAudioPlayer');
    } catch (e) {
      developer.log(
        'Failed to release audio player: $e',
        name: 'AudioPlayback',
        error: e,
      );
    }
  }
}
