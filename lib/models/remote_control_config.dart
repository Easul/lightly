import 'dart:io';
import 'dart:math';

/// 远程控制端口配置
///
/// 支持三种模式：
/// 1. 随机端口 - 避免端口冲突
/// 2. 自定义端口 - 用户指定
/// 3. 自动检测 - 查找可用端口
class RemoteControlPortConfig {
  static const int minBasePort = 18080;
  static const int maxBasePort = 18087;

  /// 控制通道端口
  final int controlPort;

  /// 屏幕通道端口
  final int screenPort;

  /// 语音通道端口
  final int audioPort;

  const RemoteControlPortConfig({
    required this.controlPort,
    required this.screenPort,
    required this.audioPort,
  });

  /// 创建随机端口配置（推荐用于生产环境）
  ///
  /// 从 18080-18089 范围内选择一个三连端口组的起始端口
  factory RemoteControlPortConfig.random() {
    final random = Random();
    final basePort =
        minBasePort + random.nextInt(maxBasePort - minBasePort + 1);
    return RemoteControlPortConfig(
      controlPort: basePort,
      screenPort: basePort + 1,
      audioPort: basePort + 2,
    );
  }

  static List<int> shuffledBasePorts([Random? random]) {
    final ports = [
      for (var basePort = minBasePort; basePort <= maxBasePort; basePort++)
        basePort,
    ];
    ports.shuffle(random);
    return ports;
  }

  /// 创建自定义端口配置
  factory RemoteControlPortConfig.custom({
    int controlPort = 18080,
    int screenPort = 18081,
    int audioPort = 18082,
  }) {
    return RemoteControlPortConfig(
      controlPort: controlPort,
      screenPort: screenPort,
      audioPort: audioPort,
    );
  }

  /// 检测可用端口并创建配置
  ///
  /// 从内置端口范围中随机尝试，找到一个可用的端口组
  static Future<RemoteControlPortConfig> detectAvailable() async {
    for (final basePort in shuffledBasePorts()) {
      try {
        // 检查控制端口
        final server1 = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          basePort,
        );
        await server1.close();

        final server2 = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          basePort + 1,
        );
        await server2.close();

        // 检查语音端口
        final server3 = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          basePort + 2,
        );
        server3.close();

        return RemoteControlPortConfig(
          controlPort: basePort,
          screenPort: basePort + 1,
          audioPort: basePort + 2,
        );
      } catch (e) {
        // 端口被占用，尝试下一个
        continue;
      }
    }

    // 如果所有端口都被占用，使用随机端口
    return RemoteControlPortConfig.random();
  }

  /// 转换为 JSON 用于传输
  Map<String, dynamic> toJson() => {
    'controlPort': controlPort,
    'screenPort': screenPort,
    'audioPort': audioPort,
  };

  /// 从 JSON 创建
  factory RemoteControlPortConfig.fromJson(Map<String, dynamic> json) {
    return RemoteControlPortConfig(
      controlPort: json['controlPort'] as int,
      screenPort: json['screenPort'] as int,
      audioPort: json['audioPort'] as int,
    );
  }

  factory RemoteControlPortConfig.fromBasePort(int basePort) {
    return RemoteControlPortConfig(
      controlPort: basePort,
      screenPort: basePort + 1,
      audioPort: basePort + 2,
    );
  }

  @override
  String toString() {
    return 'RemoteControlPortConfig(control=$controlPort, screen=$screenPort, audio=$audioPort)';
  }
}

/// 远程控制配置
class RemoteControlConfig {
  /// 端口配置
  final RemoteControlPortConfig ports;

  /// 是否启用语音
  final bool enableAudio;

  /// 是否启用屏幕传输
  final bool enableScreen;

  /// 屏幕捕获帧率
  final int screenFps;

  /// 屏幕捕获码率 (bps)
  final int screenBitrate;

  /// 语音采样率
  final int audioSampleRate;

  /// 语音码率 (bps)
  final int audioBitrate;

  const RemoteControlConfig({
    required this.ports,
    this.enableAudio = true,
    this.enableScreen = true,
    this.screenFps = 12,
    this.screenBitrate = 2500000, // 2.5 Mbps
    this.audioSampleRate = 16000,
    this.audioBitrate = 24000, // 24 kbps
  });

  /// 创建默认配置（自动检测端口）
  static Future<RemoteControlConfig> defaultConfig() async {
    final ports = await RemoteControlPortConfig.detectAvailable();
    return RemoteControlConfig(ports: ports);
  }

  /// 创建随机端口配置
  factory RemoteControlConfig.random() {
    return RemoteControlConfig(ports: RemoteControlPortConfig.random());
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
    'ports': ports.toJson(),
    'enableAudio': enableAudio,
    'enableScreen': enableScreen,
    'screenFps': screenFps,
    'screenBitrate': screenBitrate,
    'audioSampleRate': audioSampleRate,
    'audioBitrate': audioBitrate,
  };

  /// 从 JSON 创建
  factory RemoteControlConfig.fromJson(Map<String, dynamic> json) {
    return RemoteControlConfig(
      ports: RemoteControlPortConfig.fromJson(
        json['ports'] as Map<String, dynamic>,
      ),
      enableAudio: json['enableAudio'] as bool? ?? true,
      enableScreen: json['enableScreen'] as bool? ?? true,
      screenFps: json['screenFps'] as int? ?? 15,
      screenBitrate: json['screenBitrate'] as int? ?? 2500000,
      audioSampleRate: json['audioSampleRate'] as int? ?? 16000,
      audioBitrate: json['audioBitrate'] as int? ?? 24000,
    );
  }

  @override
  String toString() {
    return 'RemoteControlConfig(ports=$ports, audio=$enableAudio, screen=$enableScreen)';
  }
}
