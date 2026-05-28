import 'dart:io';

class RemoteControlCleanupHelper {
  const RemoteControlCleanupHelper();

  Future<void> resetControllerConnection({
    required bool stopNative,
    required Socket? controllerControlSocket,
    required Socket? controllerScreenSocket,
    required void Function() resetScreenPipeline,
    required void Function() resetControllerMessages,
    required void Function() stopScreenFrameWatchdog,
    required void Function() stopHeartbeat,
    required Future<void> Function() closeVoiceSession,
    required Future<void> Function() stopNativeService,
  }) async {
    stopScreenFrameWatchdog();
    stopHeartbeat();
    controllerControlSocket?.destroy();
    controllerScreenSocket?.destroy();
    await closeVoiceSession();
    resetScreenPipeline();
    resetControllerMessages();
    if (stopNative) {
      await stopNativeService();
    }
  }

  Future<void> rollbackReceiverStartup({
    required Socket? receiverControlSocket,
    required Socket? receiverScreenSocket,
    required ServerSocket? controlServer,
    required ServerSocket? screenServer,
    required void Function() stopScreenFrameWatchdog,
    required Future<void> Function() stopAudioCapture,
    required Future<void> Function() closeVoiceSession,
    required Future<void> Function() stopNativeService,
  }) async {
    stopScreenFrameWatchdog();
    await stopAudioCapture();
    await closeVoiceSession();
    receiverControlSocket?.destroy();
    receiverScreenSocket?.destroy();
    await controlServer?.close();
    await screenServer?.close();
    await stopNativeService();
  }
}
