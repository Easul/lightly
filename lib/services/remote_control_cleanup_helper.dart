import 'dart:io';

class RemoteControlCleanupHelper {
  const RemoteControlCleanupHelper();

  Future<void> resetControllerConnection({
    required bool stopNative,
    required Socket? controllerControlSocket,
    required Socket? controllerScreenSocket,
    required RawDatagramSocket? audioSocket,
    required List<int> screenDataBuffer,
    required StringBuffer controllerControlBuffer,
    required void Function() stopScreenFrameWatchdog,
    required void Function() stopHeartbeat,
    required Future<void> Function() stopAudioPlayback,
    required Future<void> Function() stopNativeService,
  }) async {
    stopScreenFrameWatchdog();
    stopHeartbeat();
    controllerControlSocket?.destroy();
    controllerScreenSocket?.destroy();
    audioSocket?.close();
    await stopAudioPlayback();
    screenDataBuffer.clear();
    controllerControlBuffer.clear();
    if (stopNative) {
      await stopNativeService();
    }
  }

  Future<void> rollbackReceiverStartup({
    required Socket? receiverControlSocket,
    required Socket? receiverScreenSocket,
    required RawDatagramSocket? audioSocket,
    required ServerSocket? controlServer,
    required ServerSocket? screenServer,
    required void Function() stopScreenFrameWatchdog,
    required Future<void> Function() stopAudioCapture,
    required Future<void> Function() stopAudioPlayback,
    required Future<void> Function() stopNativeService,
  }) async {
    stopScreenFrameWatchdog();
    await stopAudioCapture();
    await stopAudioPlayback();
    receiverControlSocket?.destroy();
    receiverScreenSocket?.destroy();
    audioSocket?.close();
    await controlServer?.close();
    await screenServer?.close();
    await stopNativeService();
  }
}
