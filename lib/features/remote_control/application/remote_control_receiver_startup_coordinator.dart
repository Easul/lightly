typedef RemoteControlReceiverStartupStep = Future<void> Function();
typedef RemoteControlReceiverStartupLog =
    void Function(String message, {Object? error});

class RemoteControlReceiverStartupCoordinator {
  const RemoteControlReceiverStartupCoordinator();

  Future<void> start({
    required bool enableScreen,
    required RemoteControlReceiverStartupStep startNativeReceiver,
    required RemoteControlReceiverStartupStep bindControlServer,
    required RemoteControlReceiverStartupStep bindScreenServer,
    required RemoteControlReceiverStartupStep rollbackStartup,
    RemoteControlReceiverStartupLog? log,
  }) async {
    try {
      await startNativeReceiver();
      await bindControlServer();
      if (enableScreen) {
        await bindScreenServer();
      }
    } catch (error) {
      await rollbackStartup();
      log?.call('Failed to start receiver: $error', error: error);
      rethrow;
    }
  }
}
