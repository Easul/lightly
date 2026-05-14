import 'dart:async';
import 'dart:math' as math;

/// 网络延迟统计点
class LatencyPoint {
  final DateTime timestamp;
  final int latencyMs;
  final String connectionType;
  final String? targetHost;

  LatencyPoint({
    required this.timestamp,
    required this.latencyMs,
    required this.connectionType,
    this.targetHost,
  });
}

/// 视频流统计点
class VideoStatsPoint {
  final DateTime timestamp;
  final double fps;
  final int frameSize;
  final int bitrate;
  final int? renderDelayMs;
  final bool isKeyFrame;

  VideoStatsPoint({
    required this.timestamp,
    required this.fps,
    required this.frameSize,
    required this.bitrate,
    this.renderDelayMs,
    required this.isKeyFrame,
  });
}

/// 音频流统计点
class AudioStatsPoint {
  final DateTime timestamp;
  final int packetSize;
  final int sequenceGap;
  final int? jitterBufferDelayMs;
  final double? currentGain;

  AudioStatsPoint({
    required this.timestamp,
    required this.packetSize,
    required this.sequenceGap,
    this.jitterBufferDelayMs,
    this.currentGain,
  });
}

/// 设备发现路径记录
class DiscoveryPath {
  final DateTime timestamp;
  final String selectedHost;
  final List<String> availableHosts;
  final bool isLocalNetwork;
  final bool isEasyTier;
  final int selectionDelayMs;

  DiscoveryPath({
    required this.timestamp,
    required this.selectedHost,
    required this.availableHosts,
    required this.isLocalNetwork,
    required this.isEasyTier,
    required this.selectionDelayMs,
  });
}

/// 性能监控服务
///
/// 收集远程控制的关键性能指标:
/// - 视频 FPS 和帧大小
/// - 网络延迟
/// - 音频抖动缓冲区延迟
/// - 设备发现路径
class PerformanceMonitorService {
  static final PerformanceMonitorService _instance =
      PerformanceMonitorService._internal();
  factory PerformanceMonitorService() => _instance;
  PerformanceMonitorService._internal();

  // 统计窗口大小
  static const int _maxStatsWindow = 100;
  static const int _reportIntervalSeconds = 10;
  static const int _audioSequenceModulo = 0x10000;

  // 数据缓存
  final List<LatencyPoint> _latencyHistory = [];
  final List<VideoStatsPoint> _videoStatsHistory = [];
  final List<AudioStatsPoint> _audioStatsHistory = [];
  final List<DiscoveryPath> _discoveryPaths = [];

  // 实时计数器
  int _frameCount = 0;
  int _totalFrameBytes = 0;
  int _keyFrameCount = 0;
  DateTime? _lastFrameTime;
  double _currentFps = 0;
  int _currentBitrate = 0;

  int _audioPacketCount = 0;
  int _totalAudioBytes = 0;
  int _lastAudioSequence = -1;
  int _audioLossCount = 0;

  // 引导路径
  String? _currentConnectionType;
  String? _currentTargetHost;
  bool _isLocalNetwork = false;
  bool _isEasyTier = false;

  Timer? _reportTimer;
  bool _isMonitoring = false;

  // 暴露给外部的流
  final StreamController<Map<String, dynamic>> _statsController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get statsStream => _statsController.stream;

  /// 启动监控
  void startMonitoring() {
    if (_isMonitoring) return;
    _resetSessionState();
    _isMonitoring = true;

    _reportTimer = Timer.periodic(
      const Duration(seconds: _reportIntervalSeconds),
      (_) => _generateReport(),
    );

    print('[PerformanceMonitor] Monitor started');
  }

  void _resetSessionState() {
    _latencyHistory.clear();
    _videoStatsHistory.clear();
    _audioStatsHistory.clear();
    _frameCount = 0;
    _totalFrameBytes = 0;
    _keyFrameCount = 0;
    _lastFrameTime = null;
    _currentFps = 0;
    _currentBitrate = 0;
    _audioPacketCount = 0;
    _totalAudioBytes = 0;
    _lastAudioSequence = -1;
    _audioLossCount = 0;
  }

  /// 停止监控
  void stopMonitoring() {
    _isMonitoring = false;
    _reportTimer?.cancel();
    _reportTimer = null;
    print('[PerformanceMonitor] Monitor stopped');
  }

  /// 记录设备发现路径
  void recordDiscoveryPath({
    required String selectedHost,
    required List<String> availableHosts,
    required int selectionDelayMs,
  }) {
    final isLocalNetwork = _isLocalNetworkAddress(selectedHost);
    final isEasyTier = _isEasyTierAddress(selectedHost);

    _currentConnectionType = isLocalNetwork
        ? '局域网直连'
        : (isEasyTier ? 'EasyTier VPN' : '其他');
    _currentTargetHost = selectedHost;
    _isLocalNetwork = isLocalNetwork;
    _isEasyTier = isEasyTier;

    final path = DiscoveryPath(
      timestamp: DateTime.now(),
      selectedHost: selectedHost,
      availableHosts: availableHosts,
      isLocalNetwork: isLocalNetwork,
      isEasyTier: isEasyTier,
      selectionDelayMs: selectionDelayMs,
    );

    _discoveryPaths.add(path);
    if (_discoveryPaths.length > 10) {
      _discoveryPaths.removeAt(0);
    }

    print(
      '设备发现: $selectedHost [${_currentConnectionType}] '
      '备选: ${availableHosts.length}个, 耗时: ${selectionDelayMs}ms',
    );
  }

  /// 记录视频帧信息
  void recordVideoFrame({
    required int frameSize,
    required bool isKeyFrame,
    int? renderDelayMs,
  }) {
    if (!_isMonitoring) return;

    final now = DateTime.now();
    _frameCount++;
    _totalFrameBytes += frameSize;
    if (isKeyFrame) _keyFrameCount++;

    if (_lastFrameTime != null) {
      final intervalMs = now.difference(_lastFrameTime!).inMilliseconds;
      if (intervalMs > 0) {
        _currentFps = 1000.0 / intervalMs;
      }
    }
    _lastFrameTime = now;

    // 计算实时码率 (bits per second)
    if (_videoStatsHistory.isNotEmpty &&
        now.difference(_videoStatsHistory.last.timestamp).inSeconds >= 1) {
      _currentBitrate =
          (_totalFrameBytes * 8) ~/
          math.max(
            1,
            now.difference(_videoStatsHistory.first.timestamp).inSeconds,
          );
    }

    final stats = VideoStatsPoint(
      timestamp: now,
      fps: _currentFps,
      frameSize: frameSize,
      bitrate: _currentBitrate,
      renderDelayMs: renderDelayMs,
      isKeyFrame: isKeyFrame,
    );

    _videoStatsHistory.add(stats);
    if (_videoStatsHistory.length > _maxStatsWindow) {
      _videoStatsHistory.removeAt(0);
    }

    // 每50帧记录一次详细日志
    if (_frameCount % 50 == 0) {
      print(
        '视频统计: FPS=${_currentFps.toStringAsFixed(1)}, '
        '码率=${(_currentBitrate / 1000).toStringAsFixed(0)}kbps, '
        '帧大小=$frameSize bytes, ${isKeyFrame ? "I帧" : "P帧"}',
      );
    }
  }

  /// 记录音频包信息
  void recordAudioPacket({
    required int packetSize,
    required int sequence,
    int? jitterBufferDelayMs,
    double? currentGain,
  }) {
    if (!_isMonitoring) return;

    final now = DateTime.now();
    _audioPacketCount++;
    _totalAudioBytes += packetSize;

    final sequenceGap = _audioSequenceGap(_lastAudioSequence, sequence);
    if (sequenceGap > 0) {
      _audioLossCount += sequenceGap;
    }
    _lastAudioSequence = sequence;

    final stats = AudioStatsPoint(
      timestamp: now,
      packetSize: packetSize,
      sequenceGap: sequenceGap,
      jitterBufferDelayMs: jitterBufferDelayMs,
      currentGain: currentGain,
    );

    _audioStatsHistory.add(stats);
    if (_audioStatsHistory.length > _maxStatsWindow) {
      _audioStatsHistory.removeAt(0);
    }

    // 每100包记录一次
    if (_audioPacketCount % 100 == 0) {
      final lossRate =
          _audioLossCount / math.max(1, _audioPacketCount + _audioLossCount);
      print(
        '音频统计: 序列=$sequence, 包大小=$packetSize, '
        '${jitterBufferDelayMs != null ? "抖动延迟=${jitterBufferDelayMs}ms, " : ""}'
        '${currentGain != null ? "增益=${currentGain.toStringAsFixed(2)}x, " : ""}'
        '丢包率=${(lossRate * 100).toStringAsFixed(1)}%',
      );
    }
  }

  /// 记录网络延迟 (测试 ping)
  void recordLatencyPing(int latencyMs) {
    if (!_isMonitoring) return;

    final point = LatencyPoint(
      timestamp: DateTime.now(),
      latencyMs: latencyMs,
      connectionType: _currentConnectionType ?? '未知',
      targetHost: _currentTargetHost,
    );

    _latencyHistory.add(point);
    if (_latencyHistory.length > _maxStatsWindow) {
      _latencyHistory.removeAt(0);
    }

    print('网络延迟: ${latencyMs}ms [${_currentConnectionType}]');
  }

  /// 生成性能报告
  void _generateReport() {
    if (!_isMonitoring) return;

    final report = getCurrentStats();
    _statsController.add(report);

    print(
      '【性能报告】\n'
      '${_formatStats(report)}',
    );
  }

  /// 获取当前统计
  Map<String, dynamic> getCurrentStats() {
    final now = DateTime.now();

    // 视频统计
    double avgFps = 0;
    int avgFrameSize = 0;
    double keyFrameRatio = 0;
    if (_videoStatsHistory.isNotEmpty) {
      avgFps =
          _videoStatsHistory.map((s) => s.fps).reduce((a, b) => a + b) /
          _videoStatsHistory.length;
      avgFrameSize =
          _videoStatsHistory.map((s) => s.frameSize).reduce((a, b) => a + b) ~/
          _videoStatsHistory.length;
      final keyFrames = _videoStatsHistory.where((s) => s.isKeyFrame).length;
      keyFrameRatio = keyFrames / _videoStatsHistory.length;
    }

    // 音频统计
    int avgAudioSize = 0;
    double audioLossRate = 0;
    int avgJitterDelay = 0;
    if (_audioStatsHistory.isNotEmpty) {
      avgAudioSize =
          _audioStatsHistory.map((s) => s.packetSize).reduce((a, b) => a + b) ~/
          _audioStatsHistory.length;
      audioLossRate =
          _audioLossCount / math.max(1, _audioPacketCount + _audioLossCount);
      final jitterDelays = _audioStatsHistory
          .where((s) => s.jitterBufferDelayMs != null)
          .map((s) => s.jitterBufferDelayMs!);
      if (jitterDelays.isNotEmpty) {
        avgJitterDelay =
            jitterDelays.reduce((a, b) => a + b) ~/ jitterDelays.length;
      }
    }

    // 延迟统计
    int avgLatency = 0;
    int maxLatency = 0;
    int minLatency = 0;
    if (_latencyHistory.isNotEmpty) {
      final latencies = _latencyHistory.map((p) => p.latencyMs);
      avgLatency = latencies.reduce((a, b) => a + b) ~/ latencies.length;
      maxLatency = latencies.reduce((a, b) => a > b ? a : b);
      minLatency = latencies.reduce((a, b) => a < b ? a : b);
    }

    return {
      'timestamp': now.toIso8601String(),
      'connection': {
        'type': _currentConnectionType,
        'host': _currentTargetHost,
        'isLocalNetwork': _isLocalNetwork,
        'isEasyTier': _isEasyTier,
      },
      'video': {
        'currentFps': _currentFps.toStringAsFixed(1),
        'avgFps': avgFps.toStringAsFixed(1),
        'avgFrameSize': avgFrameSize,
        'currentBitrateKbps': (_currentBitrate / 1000).toStringAsFixed(0),
        'keyFrameRatio': (keyFrameRatio * 100).toStringAsFixed(1) + '%',
        'totalFrames': _frameCount,
      },
      'audio': {
        'avgPacketSize': avgAudioSize,
        'totalPackets': _audioPacketCount,
        'lossRate': (audioLossRate * 100).toStringAsFixed(2) + '%',
        'avgJitterDelayMs': avgJitterDelay,
        'totalBytesKB': (_totalAudioBytes / 1024).toStringAsFixed(1),
      },
      'network': {
        'avgLatencyMs': avgLatency,
        'maxLatencyMs': maxLatency,
        'minLatencyMs': minLatency,
        'sampleCount': _latencyHistory.length,
      },
      'discovery': _discoveryPaths.isNotEmpty
          ? {
              'lastSelectedHost': _discoveryPaths.last.selectedHost,
              'availableHosts': _discoveryPaths.last.availableHosts.length,
              'selectionDelayMs': _discoveryPaths.last.selectionDelayMs,
            }
          : null,
    };
  }

  int _audioSequenceGap(int previous, int current) {
    if (previous < 0) {
      return 0;
    }
    final delta = current >= previous
        ? current - previous
        : current + _audioSequenceModulo - previous;
    return delta > 0 ? delta - 1 : 0;
  }

  /// 导出完整日志
  String exportLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== 性能监控日志导出 ===');
    buffer.writeln('生成时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln('');

    // 设备发现历史
    buffer.writeln('--- 设备发现历史 ---');
    for (final path in _discoveryPaths) {
      buffer.writeln(
        '${path.timestamp}: ${path.selectedHost} '
        '[${path.isLocalNetwork ? '局域网' : (path.isEasyTier ? 'EasyTier' : '其他')}] '
        '备选${path.availableHosts.length}个, 耗时${path.selectionDelayMs}ms',
      );
    }
    buffer.writeln('');

    // 当前统计
    buffer.writeln('--- 当前统计 ---');
    buffer.writeln(_formatStats(getCurrentStats()));

    return buffer.toString();
  }

  String _formatStats(Map<String, dynamic> stats) {
    final buffer = StringBuffer();

    final conn = stats['connection'] as Map<String, dynamic>?;
    if (conn != null) {
      buffer.writeln('连接类型: ${conn['type']} (${conn['host']})');
    }

    final video = stats['video'] as Map<String, dynamic>?;
    if (video != null) {
      buffer.writeln(
        '视频: ${video['currentFps']} FPS, '
        '码率 ${video['currentBitrateKbps']} kbps, '
        '帧大小 ${video['avgFrameSize']} bytes, '
        'I帧占比 ${video['keyFrameRatio']}',
      );
    }

    final audio = stats['audio'] as Map<String, dynamic>?;
    if (audio != null) {
      buffer.writeln(
        '音频: 抖动延迟 ${audio['avgJitterDelayMs']}ms, '
        '丢包率 ${audio['lossRate']}, '
        '包数 ${audio['totalPackets']}',
      );
    }

    final network = stats['network'] as Map<String, dynamic>?;
    if (network != null && (network['sampleCount'] as int) > 0) {
      buffer.writeln(
        '网络: 平均延迟 ${network['avgLatencyMs']}ms, '
        '范围 ${network['minLatencyMs']}-${network['maxLatencyMs']}ms',
      );
    }

    return buffer.toString();
  }

  /// 判断是否为局域网地址
  bool _isLocalNetworkAddress(String host) {
    // 局域网地址段
    if (host.startsWith('192.168.')) return true;
    if (host.startsWith('10.')) {
      // 排除 EasyTier 网段 10.126.x.x
      if (host.startsWith('10.126.')) return false;
      return true;
    }
    if (host.startsWith('172.')) {
      final secondOctet = int.tryParse(host.split('.')[1]) ?? 0;
      if (secondOctet >= 16 && secondOctet <= 31) return true;
    }
    return false;
  }

  /// 判断是否为 EasyTier 地址
  bool _isEasyTierAddress(String host) {
    // EasyTier 默认网段
    if (host.startsWith('10.126.')) return true;
    if (host.startsWith('10.144.')) return true;
    return false;
  }

  /// 清理历史数据
  void clear() {
    _latencyHistory.clear();
    _videoStatsHistory.clear();
    _audioStatsHistory.clear();
    _discoveryPaths.clear();
    _frameCount = 0;
    _totalFrameBytes = 0;
    _keyFrameCount = 0;
    _audioPacketCount = 0;
    _totalAudioBytes = 0;
    _audioLossCount = 0;
    _lastAudioSequence = -1;
    _currentFps = 0;
    _currentBitrate = 0;
  }

  void dispose() {
    stopMonitoring();
    _statsController.close();
  }
}
