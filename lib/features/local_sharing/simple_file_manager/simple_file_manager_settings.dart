class SimpleFileManagerSettings {
  const SimpleFileManagerSettings({
    required this.enabled,
    required this.rootPath,
    required this.port,
    required this.bindAllInterfaces,
    required this.favoritePaths,
  });

  static const int defaultPort = 12580;
  static const String defaultRootPath = '/storage/emulated/0';

  final bool enabled;
  final String rootPath;
  final int port;
  final bool bindAllInterfaces;
  final List<String> favoritePaths;

  factory SimpleFileManagerSettings.defaults() {
    return const SimpleFileManagerSettings(
      enabled: false,
      rootPath: defaultRootPath,
      port: defaultPort,
      bindAllInterfaces: true,
      favoritePaths: <String>[],
    );
  }

  SimpleFileManagerSettings copyWith({
    bool? enabled,
    String? rootPath,
    int? port,
    bool? bindAllInterfaces,
    List<String>? favoritePaths,
  }) {
    return SimpleFileManagerSettings(
      enabled: enabled ?? this.enabled,
      rootPath: rootPath ?? this.rootPath,
      port: port ?? this.port,
      bindAllInterfaces: bindAllInterfaces ?? this.bindAllInterfaces,
      favoritePaths: favoritePaths ?? this.favoritePaths,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'rootPath': rootPath,
      'port': port,
      'bindAllInterfaces': bindAllInterfaces,
      'favoritePaths': favoritePaths,
    };
  }

  factory SimpleFileManagerSettings.fromJson(Map<String, dynamic> json) {
    return SimpleFileManagerSettings(
      enabled: json['enabled'] as bool? ?? false,
      rootPath:
          json['rootPath'] as String? ??
          SimpleFileManagerSettings.defaultRootPath,
      port:
          (json['port'] as num?)?.toInt() ??
          SimpleFileManagerSettings.defaultPort,
      bindAllInterfaces: json['bindAllInterfaces'] as bool? ?? true,
      favoritePaths:
          (json['favoritePaths'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .where((path) => path.trim().isNotEmpty)
              .toList(growable: false),
    );
  }

  String? get validationError {
    if (rootPath.trim().isEmpty) {
      return '文件根目录不能为空';
    }
    if (port <= 0 || port > 65535) {
      return '文件简易管理端口必须是 1-65535';
    }
    return null;
  }
}
