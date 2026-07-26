abstract class RemoteControlDiagnostics {
  void startMonitoring();

  void stopMonitoring();

  void recordDiscoveryPath({
    required String selectedHost,
    required List<String> availableHosts,
    required int selectionDelayMs,
  });

  void recordVideoFrame({
    required int frameSize,
    required bool isKeyFrame,
    int? renderDelayMs,
  });

  String exportLogs();

  Map<String, dynamic> getCurrentStats();
}

class NoopRemoteControlDiagnostics implements RemoteControlDiagnostics {
  const NoopRemoteControlDiagnostics();

  @override
  void startMonitoring() {}

  @override
  void stopMonitoring() {}

  @override
  void recordDiscoveryPath({
    required String selectedHost,
    required List<String> availableHosts,
    required int selectionDelayMs,
  }) {}

  @override
  void recordVideoFrame({
    required int frameSize,
    required bool isKeyFrame,
    int? renderDelayMs,
  }) {}

  @override
  String exportLogs() => '';

  @override
  Map<String, dynamic> getCurrentStats() => const <String, dynamic>{};
}
