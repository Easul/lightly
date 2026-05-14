import 'dart:io';
import 'dart:typed_data';

import '../models/remote_control_config.dart';

class RemoteControlControllerConnectionResult {
  final Socket controlSocket;
  final Socket? screenSocket;
  final RawDatagramSocket? audioSocket;

  const RemoteControlControllerConnectionResult({
    required this.controlSocket,
    required this.screenSocket,
    required this.audioSocket,
  });
}

class RemoteControlLifecycleHelper {
  const RemoteControlLifecycleHelper();

  Future<RemoteControlControllerConnectionResult> connectControllerSockets({
    required String host,
    required RemoteControlConfig config,
    required void Function(Uint8List) onControlData,
    required void Function(dynamic error) onControlError,
    required void Function() onControlDone,
    required void Function(Uint8List) onScreenDataRaw,
    required void Function(dynamic error, Socket socket) onScreenError,
    required void Function(Socket socket) onScreenDone,
    required void Function(RawSocketEvent event) onAudioPacket,
    required Future<void> Function({
      required int sampleRate,
      required int channels,
    })
    startAudioPlayback,
    required Future<void> Function(int port) sendAudioPortStatus,
  }) async {
    final controlSocket = await Socket.connect(
      host,
      config.ports.controlPort,
      timeout: const Duration(milliseconds: 1500),
    );
    controlSocket.setOption(SocketOption.tcpNoDelay, true);
    controlSocket.listen(
      onControlData,
      onError: onControlError,
      onDone: onControlDone,
    );

    Socket? screenSocket;
    if (config.enableScreen) {
      screenSocket = await Socket.connect(
        host,
        config.ports.screenPort,
        timeout: const Duration(milliseconds: 1500),
      );
      screenSocket.setOption(SocketOption.tcpNoDelay, true);
      screenSocket.listen(
        onScreenDataRaw,
        onError: (error) => onScreenError(error, screenSocket!),
        onDone: () => onScreenDone(screenSocket!),
      );
    }

    RawDatagramSocket? audioSocket;
    if (config.enableAudio) {
      audioSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      audioSocket.listen(onAudioPacket);
      await startAudioPlayback(sampleRate: config.audioSampleRate, channels: 1);
      await sendAudioPortStatus(audioSocket.port);
    }

    return RemoteControlControllerConnectionResult(
      controlSocket: controlSocket,
      screenSocket: screenSocket,
      audioSocket: audioSocket,
    );
  }

  void attachReceiverControlClient({
    required Socket client,
    required void Function(Uint8List data) onData,
    required void Function(dynamic error) onError,
    required void Function() onDone,
  }) {
    client.listen(onData, onError: onError, onDone: onDone);
  }

  void attachReceiverScreenClient({
    required Socket client,
    required void Function(Uint8List data) onData,
    required void Function(dynamic error, Socket socket) onError,
    required void Function(Socket socket) onDone,
  }) {
    client.listen(
      onData,
      onError: (error) => onError(error, client),
      onDone: () => onDone(client),
    );
  }
}
