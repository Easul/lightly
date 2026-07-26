abstract class RemoteControlRuntime {
  Future<void> disconnect();

  void setReceiverHostShutdownHandler(Future<void> Function()? handler);
}

abstract class RemoteControlPlatformRuntime {
  Future<void> stop();

  Future<void> stopScreenCapture();
}
