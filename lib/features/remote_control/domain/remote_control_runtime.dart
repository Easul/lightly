import 'dart:typed_data';

import 'remote_control_config.dart';
import 'remote_control_protocol.dart';
import 'screen_frame.dart';

enum RemoteControlMode { controller, receiver }

enum RemoteControlState { idle, connecting, connected, disconnected, error }

class RemoteScreenDimensions {
  const RemoteScreenDimensions({required this.width, required this.height});

  final double width;
  final double height;
}

abstract class RemoteControlRuntime {
  Future<void> disconnect();

  void setReceiverHostShutdownHandler(Future<void> Function()? handler);
}

/// Presentation-facing view of the remote-control session owner.
///
/// Implementations retain all socket and mutable session ownership. Pages use
/// this contract only to observe state and submit user intent.
abstract class RemoteControlPresentationRuntime extends RemoteControlRuntime {
  Stream<RemoteControlState> get stateStream;

  Stream<ControlMessage> get messageStream;

  Stream<ScreenFrame> get screenFrameStream;

  RemoteControlState get state;

  RemoteControlMode get mode;

  RemoteControlConfig? get config;

  bool get isLocalAudioEnabled;

  bool get isVoiceEnabled;

  bool get isRemoteMicrophoneEnabled;

  bool get isLocalDisconnectRequested;

  bool get isReceiverHostRunning;

  bool get isReceiverNoTunMode;

  Uint8List? get latestScreenSps;

  Uint8List? get latestScreenPps;

  RemoteScreenDimensions? get latestRemoteScreenDimensions;

  Future<RemoteControlPortConfig> startReceiver({RemoteControlConfig? config});

  Future<void> connectToReceiver(
    String host,
    RemoteControlPortConfig ports, {
    List<String> availableHosts = const <String>[],
    int discoveryDelayMs = 0,
    bool useProxy = false,
    int? proxyPort,
    bool enableVoice = true,
  });

  Future<RemoteControlPortConfig?> discoverReceiverPorts(
    String host, {
    bool useProxy = false,
    int? proxyPort,
  });

  Future<void> sendGesture(GestureCommand command);

  Future<void> sendKeyboard(KeyboardCommand command);

  Future<void> sendOverlayText(String text);

  Future<void> sendAnnotationCircle({
    required double centerX,
    required double centerY,
    required double radius,
  });

  Future<void> wakeReceiverScreen();

  Future<void> requestReceiverShutdown();

  Future<void> setReceiverMicrophoneEnabled(bool enabled);

  Future<void> sendGlobalAction(GlobalAction action);

  Future<bool> startScreenCapture({int fps = 12, int bitrate = 2500000});

  Future<void> refreshLatestRemoteFrame();

  Future<bool> startAudioCapture({int sampleRate = 16000, int channels = 1});

  Future<void> stopAudioCapture();

  Future<void> shutdownReceiverHostResources();
}

abstract class RemoteControlPlatformRuntime {
  Future<void> stop();

  Future<void> stopScreenCapture();
}

abstract class RemoteControlCapturePlatformRuntime {
  Future<bool?> startScreenCapture({required int fps, required int bitrate});

  Future<void> stopScreenCapture();

  Future<void> requestKeyFrame();

  Future<void> updateBitrate(int bitrate);
}

abstract class RemoteControlPermissionRuntime {
  Future<bool> checkAccessibilityPermission();

  Future<void> openAccessibilitySettings();
}

abstract class RemoteControlOverlayRuntime {
  Future<bool?> showDisconnectOverlay(String message);
}

abstract class RemoteControlScreenPlatformRuntime {
  Future<int?> createScreenTexture({required int width, required int height});

  Future<void> disposeScreenTexture(int textureId);

  Future<void> pushScreenFrame({
    required int textureId,
    required Uint8List data,
    required int type,
    required int timestamp,
  });
}

abstract class RemoteControlPresentationPlatformRuntime
    implements
        RemoteControlPermissionRuntime,
        RemoteControlOverlayRuntime,
        RemoteControlScreenPlatformRuntime {}
