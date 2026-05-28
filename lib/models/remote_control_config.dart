import 'dart:io';
import 'dart:math';

/// 远程控制端口配置
///
/// 当前只保留控制通道和屏幕通道端口。
/// WebRTC 语音使用独立媒体协商，不再占用固定音频端口。
class RemoteControlPortConfig {
  static const int minBasePort = 18080;
  static const int maxBasePort = 18087;

  /// 控制通道端口
  final int controlPort;

  /// 屏幕通道端口
  final int screenPort;

  const RemoteControlPortConfig({
    required this.controlPort,
    required this.screenPort,
  });

  /// 创建随机端口配置（推荐用于生产环境）
  factory RemoteControlPortConfig.random() {
    final random = Random();
    final basePort =
        minBasePort + random.nextInt(maxBasePort - minBasePort + 1);
    return RemoteControlPortConfig(
      controlPort: basePort,
      screenPort: basePort + 1,
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

  factory RemoteControlPortConfig.custom({
    int controlPort = 18080,
    int screenPort = 18081,
  }) {
    return RemoteControlPortConfig(
      controlPort: controlPort,
      screenPort: screenPort,
    );
  }

  static Future<RemoteControlPortConfig> detectAvailable() async {
    for (final basePort in shuffledBasePorts()) {
      try {
        final controlServer = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          basePort,
        );
        await controlServer.close();

        final screenServer = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          basePort + 1,
        );
        await screenServer.close();

        return RemoteControlPortConfig(
          controlPort: basePort,
          screenPort: basePort + 1,
        );
      } catch (_) {
        continue;
      }
    }

    return RemoteControlPortConfig.random();
  }

  Map<String, dynamic> toJson() => {
    'controlPort': controlPort,
    'screenPort': screenPort,
  };

  factory RemoteControlPortConfig.fromJson(Map<String, dynamic> json) {
    return RemoteControlPortConfig(
      controlPort: json['controlPort'] as int,
      screenPort: json['screenPort'] as int,
    );
  }

  factory RemoteControlPortConfig.fromBasePort(int basePort) {
    return RemoteControlPortConfig(
      controlPort: basePort,
      screenPort: basePort + 1,
    );
  }

  @override
  String toString() {
    return 'RemoteControlPortConfig(control=$controlPort, screen=$screenPort)';
  }
}

/// 远程控制配置
class RemoteControlConfig {
  final RemoteControlPortConfig ports;
  final bool enableScreen;
  final int screenFps;
  final int screenBitrate;
  final WebRtcIceConfig iceConfig;

  const RemoteControlConfig({
    required this.ports,
    this.enableScreen = true,
    this.screenFps = 12,
    this.screenBitrate = 2500000,
    this.iceConfig = const WebRtcIceConfig(),
  });

  static Future<RemoteControlConfig> defaultConfig() async {
    final ports = await RemoteControlPortConfig.detectAvailable();
    return RemoteControlConfig(ports: ports);
  }

  factory RemoteControlConfig.random() {
    return RemoteControlConfig(ports: RemoteControlPortConfig.random());
  }

  Map<String, dynamic> toJson() => {
    'ports': ports.toJson(),
    'enableScreen': enableScreen,
    'screenFps': screenFps,
    'screenBitrate': screenBitrate,
    'iceConfig': iceConfig.toJson(),
  };

  factory RemoteControlConfig.fromJson(Map<String, dynamic> json) {
    return RemoteControlConfig(
      ports: RemoteControlPortConfig.fromJson(
        json['ports'] as Map<String, dynamic>,
      ),
      enableScreen: json['enableScreen'] as bool? ?? true,
      screenFps: json['screenFps'] as int? ?? 15,
      screenBitrate: json['screenBitrate'] as int? ?? 2500000,
      iceConfig: json['iceConfig'] is Map<String, dynamic>
          ? WebRtcIceConfig.fromJson(json['iceConfig'] as Map<String, dynamic>)
          : const WebRtcIceConfig(),
    );
  }

  @override
  String toString() {
    return 'RemoteControlConfig(ports=$ports, screen=$enableScreen, ice=$iceConfig)';
  }
}

class WebRtcIceConfig {
  static const List<String> defaultStunUrls = <String>[
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
  ];

  final List<String> stunUrls;
  final String? turnUrl;
  final String? username;
  final String? credential;
  final bool forceRelay;

  const WebRtcIceConfig({
    this.stunUrls = defaultStunUrls,
    this.turnUrl,
    this.username,
    this.credential,
    this.forceRelay = false,
  });

  bool get hasTurnServer => turnUrl != null && turnUrl!.trim().isNotEmpty;

  WebRtcIceConfig copyWith({
    List<String>? stunUrls,
    String? turnUrl,
    String? username,
    String? credential,
    bool? forceRelay,
    bool clearTurnUrl = false,
    bool clearUsername = false,
    bool clearCredential = false,
  }) {
    return WebRtcIceConfig(
      stunUrls: stunUrls ?? this.stunUrls,
      turnUrl: clearTurnUrl ? null : (turnUrl ?? this.turnUrl),
      username: clearUsername ? null : (username ?? this.username),
      credential: clearCredential ? null : (credential ?? this.credential),
      forceRelay: forceRelay ?? this.forceRelay,
    );
  }

  Map<String, dynamic> toJson() => {
    'stunUrls': stunUrls,
    'turnUrl': turnUrl,
    'username': username,
    'credential': credential,
    'forceRelay': forceRelay,
  };

  factory WebRtcIceConfig.fromJson(Map<String, dynamic> json) {
    return WebRtcIceConfig(
      stunUrls:
          (json['stunUrls'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          defaultStunUrls,
      turnUrl: (json['turnUrl'] as String?)?.trim().isEmpty == true
          ? null
          : (json['turnUrl'] as String?),
      username: (json['username'] as String?)?.trim().isEmpty == true
          ? null
          : (json['username'] as String?),
      credential: (json['credential'] as String?)?.trim().isEmpty == true
          ? null
          : (json['credential'] as String?),
      forceRelay: json['forceRelay'] as bool? ?? false,
    );
  }

  @override
  String toString() {
    return 'WebRtcIceConfig(turn=${hasTurnServer ? turnUrl : 'none'}, relay=$forceRelay)';
  }
}
