class LocalHttpServerConfig {
  const LocalHttpServerConfig({
    required this.enabled,
    required this.rootPath,
    required this.port,
    required this.bindAllInterfaces,
    required this.uploadKey,
  });

  final bool enabled;
  final String rootPath;
  final int? port;
  final bool bindAllInterfaces;
  final String uploadKey;

  String? get validationError {
    if (!enabled) {
      return null;
    }
    if (rootPath.trim().isEmpty) {
      return '本地 HTTP 服务目录不能为空';
    }
    if (port != null && (port! <= 0 || port! > 65535)) {
      return '本地 HTTP 服务端口必须是 1-65535';
    }
    return null;
  }
}
