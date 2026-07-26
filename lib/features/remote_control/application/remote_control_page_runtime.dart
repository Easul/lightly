class RemoteControlPageRuntimeState {
  const RemoteControlPageRuntimeState({required this.isProxyRunning});

  final bool isProxyRunning;
}

abstract class RemoteControlPageRuntime {
  bool get isEasyTierRunning;

  bool get isEasyTierNoTunMode;

  int? get activeNoTunSocksPort;

  int? get localProxyPort;

  Stream<bool> get proxyRunningStream;

  Future<RemoteControlPageRuntimeState> initialize();

  Future<int?> ensureInternalProxyReady({required bool useInternalProxy});

  Future<List<Map<String, String>>?> loadReachablePeers();

  Future<bool> ensureReceiverNetwork({required bool noTunMode});

  Future<void> shutdownAll();
}

class RemoteControlPageRuntimeException implements Exception {
  const RemoteControlPageRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}
