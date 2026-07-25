abstract class RemoteControlRuntime {
  Future<void> disconnect();
}

abstract class RemoteControlPlatformRuntime {
  Future<void> stop();

  Future<void> stopScreenCapture();
}
