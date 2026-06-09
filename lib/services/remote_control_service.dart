import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/remote_control_config.dart';
import 'remote_control_command_helper.dart';
import 'remote_control_cleanup_helper.dart';
import 'remote_control_connection_flow_coordinator.dart';
import 'remote_control_connection_helper.dart';
import 'remote_control_lifecycle_helper.dart';
import 'remote_control_message_router.dart';
import 'remote_control_protocol.dart';
import 'remote_control_receiver_startup_coordinator.dart';
import 'remote_control_screen_frame_pipeline_coordinator.dart';
import 'remote_control_screen_frame_sender.dart';
import 'remote_control_screen_health_coordinator.dart';
import 'remote_control_status_bridge.dart';
import 'remote_control_voice_coordinator.dart';
import 'screen_capture_manager.dart';
import 'app_log_service.dart';
import 'easytier_service.dart';
import 'performance_monitor_service.dart';
import 'webrtc_voice_service.dart';

enum RemoteControlMode { controller, receiver }

enum RemoteControlState { idle, connecting, connected, disconnected, error }

class RemoteControlService {
  static const MethodChannel _channel = MethodChannel('remote_control');
  static const String _easyTierOverlayPrefix = '10.126.';
  static final RemoteControlService _instance =
      RemoteControlService._internal();
  factory RemoteControlService() => _instance;
  RemoteControlService._internal() {
    _setupMethodCallHandler();
    _voiceService = WebRtcVoiceService(
      sendSignal: _sendWebRtcSignal,
      ensureDiagnosticsLogging: _ensureAudioDiagnosticsLogging,
      log: _logMessage,
      onConnectionInterrupted: _handleWebRtcConnectionInterrupted,
    );
    _voiceCoordinator = RemoteControlVoiceCoordinator(
      prepare: _voiceService.prepare,
      setLocalAudioEnabled: _voiceService.setLocalAudioEnabled,
      handleSignal: _voiceService.handleSignal,
      close: _voiceService.close,
      isPrepared: () => _voiceService.isPrepared,
    );
  }

  RemoteControlMode _mode = RemoteControlMode.controller;
  RemoteControlState _state = RemoteControlState.idle;
  RemoteControlConfig? _config;
  String? _targetHost;

  Socket? _controllerControlSocket;
  Socket? _receiverControlSocket;
  ServerSocket? _controlServer;
  Socket? _controllerScreenSocket;
  Socket? _receiverScreenSocket;
  ServerSocket? _screenServer;

  final StreamController<RemoteControlState> _stateController =
      StreamController<RemoteControlState>.broadcast();
  final StreamController<ControlMessage> _messageController =
      StreamController<ControlMessage>.broadcast();
  final StreamController<ScreenFrame> _screenFrameController =
      StreamController<ScreenFrame>.broadcast();

  final ScreenCaptureManager _screenCaptureManager = ScreenCaptureManager();
  final PerformanceMonitorService _performanceMonitor =
      PerformanceMonitorService();
  final RemoteControlCommandHelper _commandHelper =
      const RemoteControlCommandHelper();
  final RemoteControlCleanupHelper _cleanupHelper =
      const RemoteControlCleanupHelper();
  final RemoteControlConnectionHelper _connectionHelper =
      const RemoteControlConnectionHelper();
  final RemoteControlLifecycleHelper _lifecycleHelper =
      const RemoteControlLifecycleHelper();
  final RemoteControlConnectionFlowCoordinator _connectionFlow =
      RemoteControlConnectionFlowCoordinator();
  final RemoteControlMessageRouter _messageRouter =
      RemoteControlMessageRouter();
  final RemoteControlReceiverStartupCoordinator _receiverStartup =
      const RemoteControlReceiverStartupCoordinator();
  final RemoteControlScreenFramePipelineCoordinator _screenFramePipeline =
      RemoteControlScreenFramePipelineCoordinator();
  late final RemoteControlScreenFrameSender _screenFrameSender =
      RemoteControlScreenFrameSender(log: _logMessage);
  final RemoteControlStatusBridge _statusBridge =
      const RemoteControlStatusBridge();
  final RemoteControlScreenHealthCoordinator _screenHealth =
      RemoteControlScreenHealthCoordinator();
  late final WebRtcVoiceService _voiceService;
  late final RemoteControlVoiceCoordinator _voiceCoordinator;

  static const Duration _screenFrameStallThreshold = Duration(
    milliseconds: 700,
  );
  static const Duration _screenKeyFrameRequestCooldown = Duration(
    milliseconds: 1000,
  );
  static const Duration _screenRecoveryKeyFrameRetryCooldown = Duration(
    milliseconds: 450,
  );
  static const int _latestFrameBatchThreshold = 3;
  static const int _controllerMaxMissedHeartbeats = 10;
  static const int _receiverMaxMissedHeartbeats = 10;
  static const Duration _heartbeatInterval = Duration(seconds: 2);
  static const Duration _receiverAutoShutdownDelay = Duration(minutes: 5);

  Map<String, dynamic>? _latestRemoteScreenInfo;
  int _messageIdCounter = 0;
  Timer? _heartbeatTimer;
  Timer? _receiverAutoShutdownTimer;
  int _missedHeartbeatCount = 0;
  bool _audioDiagnosticsLoggingReady = false;
  bool _disconnectRequested = false;
  String? _lastControllerHost;
  RemoteControlPortConfig? _lastControllerPorts;
  bool _lastControllerUseProxy = false;
  int? _lastControllerProxyPort;
  List<String> _lastControllerAvailableHosts = const <String>[];
  int _lastControllerDiscoveryDelayMs = 0;
  DateTime? _lastWebRtcRecoveryAt;
  bool _receiverSessionActive = false;

  // 视频流质量控制
  static const int _maxBitrate = 8000000;
  static const int _minBitrate = 500000;

  Stream<RemoteControlState> get stateStream => _stateController.stream;
  Stream<ControlMessage> get messageStream => _messageController.stream;
  Stream<ScreenFrame> get screenFrameStream => _screenFrameController.stream;
  ScreenCaptureManager get screenCaptureManager => _screenCaptureManager;
  bool get isLocalAudioEnabled => _voiceService.isLocalAudioEnabled;
  bool get isVoiceEnabled => _config?.enableVoice ?? true;
  bool get isRemoteMicrophoneEnabled =>
      _voiceCoordinator.remoteMicrophoneEnabled;

  RemoteControlState get state => _state;
  RemoteControlMode get mode => _mode;
  RemoteControlConfig? get config => _config;
  bool get isConnected => _state == RemoteControlState.connected;
  bool get isLocalDisconnectRequested => _disconnectRequested;
  bool get isReceiverHostRunning =>
      _mode == RemoteControlMode.receiver && _controlServer != null;
  bool get isReceiverNoTunMode =>
      _mode == RemoteControlMode.receiver && _config?.enableVoice == false;
  Uint8List? get latestScreenSps =>
      _screenFramePipeline.latestSps ?? _screenCaptureManager.spsData;
  Uint8List? get latestScreenPps =>
      _screenFramePipeline.latestPps ?? _screenCaptureManager.ppsData;
  Size? get latestRemoteScreenSize {
    final width = (_latestRemoteScreenInfo?['width'] as num?)?.toDouble();
    final height = (_latestRemoteScreenInfo?['height'] as num?)?.toDouble();
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width, height);
  }

  int _nextMessageId() => ++_messageIdCounter;

  void _logMessage(String message, {Object? error}) {
    developer.log(message, name: 'RemoteControl', error: error);
    unawaited(
      AppLogService.instance.log('[RemoteControl] $message', error: error),
    );
  }

  Future<void> _ensureAudioDiagnosticsLogging() async {
    if (_audioDiagnosticsLoggingReady) {
      return;
    }
    if (kProfileMode && !AppLogService.instance.isEnabled) {
      await AppLogService.instance.setEnabled(true);
    }
    _audioDiagnosticsLoggingReady = true;
    await AppLogService.instance.log(
      '[RemoteControl] audio diagnostics logging ready',
      metadata: <String, Object?>{
        'mode': _mode.name,
        'profile': kProfileMode,
        'logPath': AppLogService.instance.logPath,
      },
    );
  }

  void _markConnectionReady() {
    _connectionFlow.markReady();
  }

  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onScreenFrame':
          final data = call.arguments['data'] as Uint8List;
          final isKeyFrame = call.arguments['isKeyFrame'] as bool;
          _screenCaptureManager.handleNativeFrame(data, isKeyFrame);

          final frame = ScreenFrame(
            type: isKeyFrame
                ? ScreenFrameType.keyFrame
                : ScreenFrameType.deltaFrame,
            data: data,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );

          if (_receiverScreenSocket != null) {
            _sendScreenFrameOverTcp(frame);
          }
          break;
        case 'onScreenConfig':
          final sps = call.arguments['sps'] as Uint8List;
          final pps = call.arguments['pps'] as Uint8List;
          _screenCaptureManager.handleConfigFrame(sps, pps);
          _screenHealth.markAwaitingRecoveryKeyFrame(true);

          if (_receiverControlSocket != null) {
            unawaited(_sendScreenInfoStatus());
          }

          if (_receiverScreenSocket != null) {
            _sendScreenConfigOverTcp(sps, pps);
            unawaited(requestKeyFrame());
          }
          break;
      }
    });
  }

  Future<void> _sendScreenInfoStatus() async {
    try {
      await _statusBridge.sendScreenInfoStatus(
        channel: _channel,
        receiverControlSocket: _receiverControlSocket,
      );
    } catch (e) {
      developer.log(
        'Failed to send screen info status: $e',
        name: 'RemoteControl',
        error: e,
      );
    }
  }

  Future<void> _sendPortConfigStatus() async {
    try {
      await _statusBridge.sendPortConfigStatus(
        receiverControlSocket: _receiverControlSocket,
        config: _config,
      );
    } catch (e) {
      developer.log(
        'Failed to send port config status: $e',
        name: 'RemoteControl',
        error: e,
      );
    }
  }

  Future<void> _sendVoiceCapabilityStatus() async {
    try {
      await _statusBridge.sendVoiceCapabilityStatus(
        receiverControlSocket: _receiverControlSocket,
        enabled: isVoiceEnabled,
      );
    } catch (e) {
      developer.log(
        'Failed to send voice capability status: $e',
        name: 'RemoteControl',
        error: e,
      );
    }
  }

  void _sendScreenFrameOverTcp(ScreenFrame frame) {
    _screenFrameSender.enqueueFrame(frame);
  }

  void _sendScreenConfigOverTcp(Uint8List sps, Uint8List pps) {
    _screenFrameSender.sendConfig(sps, pps);
  }

  Future<RemoteControlPortConfig> startReceiver({
    RemoteControlConfig? config,
  }) async {
    _mode = RemoteControlMode.receiver;
    _disconnectRequested = false;
    _receiverSessionActive = false;
    _config = config ?? await RemoteControlConfig.defaultConfig();
    final ports = _config!.ports;

    try {
      await _receiverStartup.start(
        enableScreen: _config!.enableScreen,
        startNativeReceiver: () => _channel.invokeMethod('startReceiver', {
          'controlPort': ports.controlPort,
          'screenPort': ports.screenPort,
          'screenFps': _config!.screenFps,
          'screenBitrate': _config!.screenBitrate,
        }),
        bindControlServer: () async {
          _controlServer = await ServerSocket.bind(
            InternetAddress.anyIPv4,
            ports.controlPort,
          );
          _controlServer!.listen(_handleControlConnection);
        },
        bindScreenServer: () async {
          _screenServer = await ServerSocket.bind(
            InternetAddress.anyIPv4,
            ports.screenPort,
          );
          _screenServer!.listen(_handleScreenConnection);
        },
        rollbackStartup: _rollbackReceiverStartup,
        log: (message, {error}) =>
            developer.log(message, name: 'RemoteControl', error: error),
      );

      _updateState(RemoteControlState.idle);
      developer.log(
        'Receiver started on ports ${ports.controlPort}/${ports.screenPort}',
        name: 'RemoteControl',
      );
      return ports;
    } catch (e) {
      _updateState(RemoteControlState.error);
      rethrow;
    }
  }

  Future<void> connectToReceiver(
    String host,
    RemoteControlPortConfig ports, {
    List<String> availableHosts = const [],
    int discoveryDelayMs = 0,
    bool useProxy = false,
    int? proxyPort,
  }) async {
    host = _connectionHelper.normalizeRemoteHost(host);
    _mode = RemoteControlMode.controller;
    _targetHost = host;
    _lastControllerHost = host;
    _lastControllerPorts = ports;
    _lastControllerUseProxy = useProxy;
    _lastControllerProxyPort = proxyPort;
    _lastControllerAvailableHosts = List<String>.from(availableHosts);
    _lastControllerDiscoveryDelayMs = discoveryDelayMs;
    _disconnectRequested = false;
    _config = RemoteControlConfig(ports: ports, enableVoice: !useProxy);

    // 记录设备发现路径
    _performanceMonitor.recordDiscoveryPath(
      selectedHost: host,
      availableHosts: availableHosts.isNotEmpty ? availableHosts : [host],
      selectionDelayMs: discoveryDelayMs,
    );
    _performanceMonitor.startMonitoring();

    _updateState(RemoteControlState.connecting);

    try {
      await _connectionFlow.connect(
        prepareAttempt: (_) {
          _screenFramePipeline.reset();
        },
        attemptConnection: (_, markNativeStarted) async {
          final connection = await _lifecycleHelper.connectControllerSockets(
            host: host,
            config: _config!,
            useProxy: useProxy,
            proxyPort: proxyPort,
            onControlData: _handleControlData,
            onControlError: _handleControlError,
            onControlDone: _handleControlDone,
            onScreenDataRaw: _handleScreenDataRaw,
            onScreenError: (error, socket) => _handleScreenError(
              error,
              socket: socket,
              mode: RemoteControlMode.controller,
            ),
            onScreenDone: (socket) => _handleScreenDone(
              socket: socket,
              mode: RemoteControlMode.controller,
            ),
          );
          _controllerControlSocket = connection.controlSocket;
          _controllerScreenSocket = connection.screenSocket;

          await _channel.invokeMethod('startController', {'host': host});
          markNativeStarted();
          if (isVoiceEnabled) {
            await _prepareVoiceSession(isController: true);
          } else {
            _logMessage('WebRTC voice disabled for internal proxy connection');
          }

          _startScreenFrameWatchdog();
          _startHeartbeat();
        },
        resetConnection: _resetControllerConnection,
        log: (message, {error}) =>
            developer.log(message, name: 'RemoteControl', error: error),
      );
      _updateState(RemoteControlState.connected);
      developer.log('Connected to $host', name: 'RemoteControl');
    } catch (e) {
      _updateState(RemoteControlState.error);
      rethrow;
    }
  }

  Future<void> reconnectLastController() async {
    final host = _lastControllerHost;
    final ports = _lastControllerPorts;
    if (host == null || ports == null) {
      throw StateError('没有可重连的远程设备');
    }
    _disconnectRequested = false;
    await connectToReceiver(
      host,
      ports,
      availableHosts: _lastControllerAvailableHosts,
      discoveryDelayMs: _lastControllerDiscoveryDelayMs,
      useProxy: _lastControllerUseProxy,
      proxyPort: _lastControllerProxyPort,
    );
  }

  Future<RemoteControlPortConfig?> discoverReceiverPorts(
    String host, {
    bool useProxy = false,
    int? proxyPort,
  }) async {
    return _connectionHelper.discoverReceiverPorts(
      host: host,
      statusBridge: _statusBridge,
      decodeBufferedMessages: _commandHelper.decodeBufferedMessages,
      useProxy: useProxy,
      proxyPort: proxyPort,
    );
  }

  void _handleWebRtcConnectionInterrupted(String reason) {
    if (_mode != RemoteControlMode.controller ||
        !isVoiceEnabled ||
        _controllerControlSocket == null) {
      return;
    }
    final now = DateTime.now();
    final last = _lastWebRtcRecoveryAt;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) {
      return;
    }
    _lastWebRtcRecoveryAt = now;
    final wasLocalAudioEnabled = _voiceService.isLocalAudioEnabled;
    _logMessage('Rebuilding WebRTC voice after interruption: $reason');
    unawaited(() async {
      await _voiceCoordinator.close();
      await _prepareVoiceSession(isController: true);
      if (wasLocalAudioEnabled) {
        await _voiceCoordinator.startAudioCapture(
          isVoiceEnabled: isVoiceEnabled,
          isController: true,
          targetHost: _targetHost,
          overlayPrefix: _easyTierOverlayPrefix,
          log: _logMessage,
        );
      }
    }());
  }

  Future<void> _resetControllerConnection({required bool stopNative}) async {
    developer.log(
      'Resetting controller connection: stopNative=$stopNative state=$_state screenSocket=${_controllerScreenSocket != null} controlSocket=${_controllerControlSocket != null} buffer=${_screenFramePipeline.bufferLength}',
      name: 'RemoteControl',
    );
    await _cleanupHelper.resetControllerConnection(
      stopNative: stopNative,
      controllerControlSocket: _controllerControlSocket,
      controllerScreenSocket: _controllerScreenSocket,
      resetScreenPipeline: _screenFramePipeline.reset,
      resetControllerMessages: _messageRouter.resetController,
      stopScreenFrameWatchdog: _stopScreenFrameWatchdog,
      stopHeartbeat: _stopHeartbeat,
      closeVoiceSession: _voiceCoordinator.close,
      stopNativeService: () => _channel.invokeMethod('stop'),
    );
    _controllerControlSocket = null;
    _controllerScreenSocket = null;
  }

  Future<void> _rollbackReceiverStartup() async {
    await _cleanupHelper.rollbackReceiverStartup(
      receiverControlSocket: _receiverControlSocket,
      receiverScreenSocket: _receiverScreenSocket,
      controlServer: _controlServer,
      screenServer: _screenServer,
      stopScreenFrameWatchdog: _stopScreenFrameWatchdog,
      stopAudioCapture: stopAudioCapture,
      closeVoiceSession: _voiceCoordinator.close,
      stopNativeService: () => _channel.invokeMethod('stop'),
    );
    _receiverControlSocket = null;
    _receiverScreenSocket = null;
    _screenFrameSender.reset();
    _controlServer = null;
    _screenServer = null;
  }

  Future<void> sendGesture(GestureCommand command) async {
    if (_controllerControlSocket == null) return;
    final data = utf8.encode('${RemoteControlCodec.encode(command)}\n');
    _controllerControlSocket!.add(data);
  }

  Future<void> sendKeyboard(KeyboardCommand command) async {
    if (_controllerControlSocket == null) return;
    final data = utf8.encode('${RemoteControlCodec.encode(command)}\n');
    _controllerControlSocket!.add(data);
  }

  Future<void> sendOverlayText(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty || _controllerControlSocket == null) return;
    final message = StatusMessage.overlayText(text: normalized);
    _controllerControlSocket!.add(
      utf8.encode('${RemoteControlCodec.encode(message)}\n'),
    );
  }

  Future<void> sendAnnotationCircle({
    required double centerX,
    required double centerY,
    required double radius,
  }) async {
    final socket = _controllerControlSocket;
    if (socket == null) {
      developer.log(
        'Skipping annotation circle without control socket: center=($centerX,$centerY) radius=$radius',
        name: 'RemoteControl',
      );
      return;
    }
    if (radius <= 0) {
      developer.log(
        'Skipping annotation circle with invalid radius: center=($centerX,$centerY) radius=$radius',
        name: 'RemoteControl',
      );
      return;
    }
    final message = StatusMessage.annotationCircle(
      centerX: centerX,
      centerY: centerY,
      radius: radius,
    );
    final payload = '${RemoteControlCodec.encode(message)}\n';
    developer.log(
      'Sending annotation circle: center=($centerX,$centerY) radius=$radius',
      name: 'RemoteControl',
    );
    try {
      socket.add(utf8.encode(payload));
      await socket.flush();
    } catch (e) {
      developer.log(
        'Failed to send annotation circle: $e',
        name: 'RemoteControl',
        error: e,
      );
    }
  }

  Future<void> wakeReceiverScreen() async {
    if (_controllerControlSocket == null) return;
    final message = StatusMessage.wakeScreen();
    _controllerControlSocket!.add(
      utf8.encode('${RemoteControlCodec.encode(message)}\n'),
    );
  }

  Future<void> requestReceiverShutdown() async {
    if (_controllerControlSocket == null) return;
    final message = StatusMessage.shutdownReceiver();
    _controllerControlSocket!.add(
      utf8.encode('${RemoteControlCodec.encode(message)}\n'),
    );
    await _controllerControlSocket!.flush();
  }

  Future<void> setReceiverMicrophoneEnabled(bool enabled) async {
    if (!isVoiceEnabled || _controllerControlSocket == null) return;
    final message = StatusMessage.receiverMicrophone(enabled: enabled);
    _controllerControlSocket!.add(
      utf8.encode('${RemoteControlCodec.encode(message)}\n'),
    );
  }

  Future<void> sendGlobalAction(GlobalAction action) async {
    final json = {
      'type': 'global',
      'action': action.name,
      'id': _nextMessageId(),
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    if (_controllerControlSocket == null) return;
    final data = utf8.encode('${jsonEncode(json)}\n');
    _controllerControlSocket!.add(data);
  }

  Future<bool> startScreenCapture({int fps = 12, int bitrate = 2500000}) async {
    try {
      final result = await _channel.invokeMethod<bool>('startScreenCapture', {
        'fps': fps,
        'bitrate': bitrate,
      });
      return result ?? false;
    } catch (e) {
      developer.log(
        'Failed to start screen capture: $e',
        name: 'RemoteControl',
        error: e,
      );
      return false;
    }
  }

  Future<void> stopScreenCapture() async {
    try {
      await _channel.invokeMethod('stopScreenCapture');
    } catch (e) {
      developer.log(
        'Failed to stop screen capture: $e',
        name: 'RemoteControl',
        error: e,
      );
    }
  }

  Future<void> requestKeyFrame() async {
    final requestedAt = DateTime.now();
    final controllerSocket = _controllerControlSocket;
    if (controllerSocket != null) {
      developer.log(
        'Forwarding key frame request over control channel: state=$_state screenSocket=${_controllerScreenSocket != null} lastFrameAgo=${_screenHealth.lastFrameAgeDescription} buffer=${_screenFramePipeline.bufferLength}',
        name: 'RemoteControl',
      );
      final message = StatusMessage.requestKeyFrame();
      controllerSocket.add(
        utf8.encode('${RemoteControlCodec.encode(message)}\n'),
      );
      _screenHealth.recordKeyFrameRequest(requestedAt);
      return;
    }

    try {
      developer.log(
        'Issuing native key frame request: mode=$_mode state=$_state buffer=${_screenFramePipeline.bufferLength}',
        name: 'RemoteControl',
      );
      await _channel.invokeMethod('requestKeyFrame');
      _screenHealth.recordKeyFrameRequest(requestedAt);
    } catch (e) {
      developer.log(
        'Failed to request key frame: $e',
        name: 'RemoteControl',
        error: e,
      );
    }
  }

  Future<void> refreshLatestRemoteFrame() async {
    if (_mode == RemoteControlMode.controller &&
        _controllerControlSocket != null &&
        _config?.enableScreen == true) {
      await _reconnectControllerScreenChannel();
      return;
    }
    await requestKeyFrame();
  }

  Future<void> _reconnectControllerScreenChannel() async {
    final host = _lastControllerHost;
    final config = _config;
    final transportPorts = _lastControllerPorts ?? config?.ports;
    if (host == null || config == null || transportPorts == null) {
      await requestKeyFrame();
      return;
    }

    developer.log(
      'Reconnecting controller screen channel: host=$host screenPort=${transportPorts.screenPort} proxy=$_lastControllerUseProxy',
      name: 'RemoteControl',
    );
    final oldSocket = _controllerScreenSocket;
    _controllerScreenSocket = null;
    oldSocket?.destroy();
    _screenFramePipeline.reset();
    _screenHealth.markAwaitingRecoveryKeyFrame(true);
    _stopScreenFrameWatchdog();

    try {
      final screenSocket = await _lifecycleHelper.connectControllerScreenSocket(
        host: host,
        config: RemoteControlConfig(
          ports: transportPorts,
          enableScreen: config.enableScreen,
          enableVoice: config.enableVoice,
          screenFps: config.screenFps,
          screenBitrate: config.screenBitrate,
        ),
        useProxy: _lastControllerUseProxy,
        proxyPort: _lastControllerProxyPort,
        onScreenDataRaw: _handleScreenDataRaw,
        onScreenError: (error, socket) => _handleScreenError(
          error,
          socket: socket,
          mode: RemoteControlMode.controller,
        ),
        onScreenDone: (socket) => _handleScreenDone(
          socket: socket,
          mode: RemoteControlMode.controller,
        ),
      );
      _controllerScreenSocket = screenSocket;
      _startScreenFrameWatchdog();
    } catch (e) {
      developer.log(
        'Failed to reconnect controller screen channel: $e',
        name: 'RemoteControl',
        error: e,
      );
      _startScreenFrameWatchdog();
    }

    await requestKeyFrame();
  }

  Future<void> updateBitrate(int bitrate) async {
    final normalizedBitrate = bitrate.clamp(_minBitrate, _maxBitrate);
    final controllerSocket = _controllerControlSocket;
    if (controllerSocket != null) {
      final message = StatusMessage.updateBitrate(bitrate: normalizedBitrate);
      controllerSocket.add(
        utf8.encode('${RemoteControlCodec.encode(message)}\n'),
      );
      return;
    }

    try {
      await _channel.invokeMethod('updateBitrate', {
        'bitrate': normalizedBitrate,
      });
    } catch (e) {
      developer.log(
        'Failed to update bitrate: $e',
        name: 'RemoteControl',
        error: e,
      );
    }
  }

  Future<bool> startAudioCapture({
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    return _voiceCoordinator.startAudioCapture(
      isVoiceEnabled: isVoiceEnabled,
      isController: _mode == RemoteControlMode.controller,
      targetHost: _targetHost,
      overlayPrefix: _easyTierOverlayPrefix,
      log: _logMessage,
    );
  }

  Future<void> stopAudioCapture() async {
    await _voiceCoordinator.stopAudioCapture();
  }

  Future<void> startAudioPlayback({
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    await _voiceCoordinator.startAudioPlayback(
      isVoiceEnabled: isVoiceEnabled,
      isController: _mode == RemoteControlMode.controller,
      targetHost: _targetHost,
      overlayPrefix: _easyTierOverlayPrefix,
      log: _logMessage,
    );
  }

  Future<void> stopAudioPlayback() async {
    await _voiceCoordinator.stopAudioPlayback();
  }

  void _handleControlConnection(Socket client) {
    developer.log(
      'Control client connected: ${client.remoteAddress}',
      name: 'RemoteControl',
    );
    _receiverControlSocket = client;
    _targetHost = client.remoteAddress.address;
    _receiverSessionActive = false;
    _missedHeartbeatCount = 0;
    unawaited(_sendPortConfigStatus());
    unawaited(_sendVoiceCapabilityStatus());
    unawaited(_sendScreenInfoStatus());

    _lifecycleHelper.attachReceiverControlClient(
      client: client,
      onData: _handleReceiverControlData,
      onError: (error) =>
          developer.log('Control client error: $error', name: 'RemoteControl'),
      onDone: () {
        developer.log('Control client disconnected', name: 'RemoteControl');
        unawaited(stopAudioCapture());
        unawaited(_voiceCoordinator.close());
        final wasActiveSession = _receiverSessionActive;
        _receiverSessionActive = false;
        _receiverControlSocket = null;
        if (wasActiveSession) {
          unawaited(_showRemoteDisconnectOverlay('对方已断开远程连接。'));
          _updateState(RemoteControlState.disconnected);
        } else if (_mode == RemoteControlMode.receiver) {
          _updateState(RemoteControlState.idle);
        }
        _stopScreenFrameWatchdog();
        _stopHeartbeat();
      },
    );
  }

  void _markReceiverSessionActive() {
    if (_mode != RemoteControlMode.receiver || _receiverSessionActive) {
      return;
    }
    _receiverSessionActive = true;
    _cancelReceiverAutoShutdown();
    _missedHeartbeatCount = 0;
    _updateState(RemoteControlState.connected);
    _startHeartbeat();
  }

  Future<bool> _showRemoteDisconnectOverlay(String message) async {
    try {
      return await _channel.invokeMethod<bool>('showDisconnectOverlay', {
            'message': message,
          }) ??
          false;
    } catch (e) {
      developer.log(
        'Failed to show disconnect overlay: $e',
        name: 'RemoteControl',
        error: e,
      );
      return false;
    }
  }

  void _handleScreenConnection(Socket client) {
    developer.log(
      'Screen client connected: ${client.remoteAddress}',
      name: 'RemoteControl',
    );
    _receiverScreenSocket = client;
    _screenFrameSender.attach(client);
    _markReceiverSessionActive();
    developer.log(
      'Receiver screen socket ready: remote=${client.remoteAddress.address}:${client.remotePort} local=${client.address.address}:${client.port}',
      name: 'RemoteControl',
    );
    final sps = _screenCaptureManager.spsData;
    final pps = _screenCaptureManager.ppsData;
    if (sps != null && pps != null) {
      _sendScreenConfigOverTcp(sps, pps);
      unawaited(requestKeyFrame());
    }
    _lifecycleHelper.attachReceiverScreenClient(
      client: client,
      onData: _handleScreenDataRaw,
      onError: (error, socket) => _handleScreenError(
        error,
        socket: socket,
        mode: RemoteControlMode.receiver,
      ),
      onDone: (socket) =>
          _handleScreenDone(socket: socket, mode: RemoteControlMode.receiver),
    );
  }

  void _handleScreenDataRaw(Uint8List data) {
    _screenHealth.recordScreenChunk(
      data: data,
      bufferedBefore: _screenFramePipeline.bufferLength,
      log: (message) => developer.log(message, name: 'RemoteControl'),
    );

    final pipelineResult = _screenFramePipeline.handleIncomingData(
      data,
      awaitingRecoveryKeyFrame: _screenHealth.awaitingRecoveryKeyFrame,
      latestFrameBatchThreshold: _latestFrameBatchThreshold,
    );
    _screenHealth.markAwaitingRecoveryKeyFrame(
      pipelineResult.awaitingRecoveryKeyFrame,
    );

    _processParsedScreenFrames(pipelineResult);
  }

  void _processParsedScreenFrames(
    RemoteControlScreenFramePipelineResult pipelineResult,
  ) {
    if (pipelineResult.framesToEmit.isEmpty) {
      return;
    }

    if (pipelineResult.droppedFrameCount > 0) {
      developer.log(
        'Dropping stale parsed screen frames: parsed=${pipelineResult.parsedFrameCount} kept=${pipelineResult.framesToEmit.length} buffered=${pipelineResult.remainingBufferLength}',
        name: 'RemoteControl',
      );
    }

    for (final frame in pipelineResult.framesToEmit) {
      _screenHealth.recordParsedFrame(
        frame: frame,
        remainingBuffer: pipelineResult.remainingBufferLength,
        log: (message) => developer.log(message, name: 'RemoteControl'),
        onBitrateAdjustDue: _adjustBitrateIfNeeded,
      );
      _performanceMonitor.recordVideoFrame(
        frameSize: frame.data.length,
        isKeyFrame: frame.type == ScreenFrameType.keyFrame,
      );
      _screenFrameController.add(frame);
      _markConnectionReady();
    }
  }

  void _adjustBitrateIfNeeded() {
    final newBitrate = _screenHealth.adjustBitrateIfNeeded(
      screenFps: _config?.screenFps ?? 12,
      maxBitrate: _maxBitrate,
      latestRemoteScreenInfo: _latestRemoteScreenInfo,
      log: (message) => developer.log(message, name: 'RemoteControl'),
    );
    if (newBitrate != null) {
      unawaited(updateBitrate(newBitrate));
    }
  }

  void _startScreenFrameWatchdog() {
    _screenHealth.startWatchdog(
      log: (message) => developer.log(message, name: 'RemoteControl'),
      onTick: _checkScreenFrameHealth,
      screenFrameStallThreshold: _screenFrameStallThreshold,
      screenKeyFrameRequestCooldown: _screenKeyFrameRequestCooldown,
      screenRecoveryKeyFrameRetryCooldown: _screenRecoveryKeyFrameRetryCooldown,
    );
  }

  void _stopScreenFrameWatchdog() {
    _screenHealth.stopWatchdog(
      log: (message) => developer.log(message, name: 'RemoteControl'),
      bufferLength: _screenFramePipeline.bufferLength,
    );
  }

  void _checkScreenFrameHealth() {
    if (_mode != RemoteControlMode.controller ||
        _state != RemoteControlState.connected ||
        _controllerScreenSocket == null ||
        _config?.enableScreen != true) {
      return;
    }

    if (_screenHealth.shouldRequestKeyFrame(
      screenRecoveryKeyFrameRetryCooldown: _screenRecoveryKeyFrameRetryCooldown,
      screenKeyFrameRequestCooldown: _screenKeyFrameRequestCooldown,
      screenFrameStallThreshold: _screenFrameStallThreshold,
      screenDataBufferLength: _screenFramePipeline.bufferLength,
      log: (message) => developer.log(message, name: 'RemoteControl'),
    )) {
      unawaited(requestKeyFrame());
    }
  }

  Future<void> _prepareVoiceSession({required bool isController}) async {
    await _voiceCoordinator.prepareSession(
      isVoiceEnabled: isVoiceEnabled,
      isController: isController,
      targetHost: _targetHost,
      overlayPrefix: _easyTierOverlayPrefix,
      log: _logMessage,
    );
  }

  Future<void> _sendWebRtcSignal(StatusMessage message) async {
    final socket = switch (_mode) {
      RemoteControlMode.controller => _controllerControlSocket,
      RemoteControlMode.receiver => _receiverControlSocket,
    };
    if (socket == null) {
      _logMessage(
        'Skipping WebRTC signal without control socket: ${message.action}',
      );
      return;
    }
    _logMessage('Sending WebRTC signal: ${message.action}');
    socket.add(utf8.encode('${RemoteControlCodec.encode(message)}\n'));
  }

  bool _isWebRtcSignal(StatusMessage message) {
    return _voiceCoordinator.isWebRtcSignal(message);
  }

  void _handleControlData(Uint8List data) {
    final messages = _messageRouter.decodeControllerMessages(data);
    for (final message in messages) {
      if (message is AckMessage) {
        _missedHeartbeatCount = 0;
      }
      _recordStatusMessage(message);
      _messageController.add(message);
    }
  }

  void _recordStatusMessage(ControlMessage message) {
    if (message is StatusMessage && _isWebRtcSignal(message)) {
      _voiceCoordinator.handleIncomingWebRtcSignal(
        message: message,
        isVoiceEnabled: isVoiceEnabled,
        targetHost: _targetHost,
        overlayPrefix: _easyTierOverlayPrefix,
        log: _logMessage,
      );
      return;
    }
    if (message is StatusMessage && message.action == 'receiver_microphone') {
      final enabled = message.data['enabled'] == true;
      unawaited(_applyReceiverMicrophone(enabled));
      return;
    }
    if (message is StatusMessage &&
        message.action == 'receiver_microphone_status') {
      _voiceCoordinator.handleReceiverMicrophoneStatus(
        message: message,
        emitMessage: _messageController.add,
      );
      return;
    }
    _statusBridge.recordStatusMessage(
      message: message,
      onScreenInfo: (info) => _latestRemoteScreenInfo = info,
      markConnectionReady: _markConnectionReady,
      onPortConfig: (ports) {
        _config = RemoteControlConfig(
          ports: ports,
          enableScreen: _config?.enableScreen ?? true,
          screenFps: _config?.screenFps ?? 15,
          screenBitrate: _config?.screenBitrate ?? 2000000,
          enableVoice: _config?.enableVoice ?? true,
        );
      },
      onVoiceCapability: (enabled) {
        if ((_config?.enableVoice ?? true) == enabled) {
          return;
        }
        _config = RemoteControlConfig(
          ports: _config?.ports ?? RemoteControlPortConfig.custom(),
          enableScreen: _config?.enableScreen ?? true,
          screenFps: _config?.screenFps ?? 15,
          screenBitrate: _config?.screenBitrate ?? 2000000,
          enableVoice: enabled,
        );
        if (!enabled) {
          unawaited(stopAudioCapture());
          unawaited(stopAudioPlayback());
        }
        _messageController.add(message);
      },
    );
  }

  Future<void> _applyReceiverMicrophone(bool enabled) async {
    await _voiceCoordinator.applyReceiverMicrophone(
      enabled: enabled,
      isVoiceEnabled: isVoiceEnabled,
      targetHost: _targetHost,
      overlayPrefix: _easyTierOverlayPrefix,
      emitMessage: _messageController.add,
      sendStatus: (status) {
        _receiverControlSocket?.add(
          utf8.encode('${RemoteControlCodec.encode(status)}\n'),
        );
      },
      log: _logMessage,
    );
  }

  void _handleReceiverControlData(Uint8List data) {
    _markReceiverSessionActive();
    _messageRouter.dispatchReceiverData(
      data,
      channel: _channel,
      minBitrate: _minBitrate,
      maxBitrate: _maxBitrate,
      recordStatusMessage: _recordStatusMessage,
      emitMessage: _messageController.add,
      requestKeyFrame: requestKeyFrame,
      updateBitrate: updateBitrate,
      sendAck: _sendAck,
      onHeartbeat: _handleHeartbeatReceived,
      shutdownReceiver: shutdownReceiverHostResources,
      log: (message, {error}) =>
          developer.log(message, name: 'RemoteControl', error: error),
    );
  }

  void _markUnexpectedControllerDisconnect(String reason) {
    if (_disconnectRequested || _mode != RemoteControlMode.controller) {
      return;
    }
    _logMessage('Remote connection interrupted: $reason');
    _updateState(RemoteControlState.disconnected);
  }

  void _handleControlError(dynamic error) {
    developer.log('Control channel error: $error', name: 'RemoteControl');
    _markUnexpectedControllerDisconnect('control-error');
    unawaited(_resetControllerConnection(stopNative: true));
  }

  void _handleControlDone() {
    developer.log('Control channel closed', name: 'RemoteControl');
    _markUnexpectedControllerDisconnect('control-done');
    unawaited(_resetControllerConnection(stopNative: true));
  }

  void _handleScreenError(
    dynamic error, {
    required Socket socket,
    required RemoteControlMode mode,
  }) {
    final activeControllerSocket = identical(_controllerScreenSocket, socket);
    final activeReceiverSocket = identical(_receiverScreenSocket, socket);
    developer.log(
      'Screen channel error: $error state=$_state mode=$_mode sourceMode=$mode activeControllerSocket=$activeControllerSocket activeReceiverSocket=$activeReceiverSocket buffer=${_screenFramePipeline.bufferLength} lastFrameAgo=${_screenHealth.lastFrameAgeDescription}',
      name: 'RemoteControl',
    );
    if (activeControllerSocket) {
      _controllerScreenSocket = null;
      _screenFramePipeline.reset();
      _stopScreenFrameWatchdog();
      _markUnexpectedControllerDisconnect('screen-error');
    }
    if (activeReceiverSocket) {
      _receiverScreenSocket = null;
      _screenFrameSender.detach(socket);
    }
  }

  void _handleScreenDone({
    required Socket socket,
    required RemoteControlMode mode,
  }) {
    final activeControllerSocket = identical(_controllerScreenSocket, socket);
    final activeReceiverSocket = identical(_receiverScreenSocket, socket);
    developer.log(
      'Screen channel closed: state=$_state mode=$_mode sourceMode=$mode activeControllerSocket=$activeControllerSocket activeReceiverSocket=$activeReceiverSocket buffer=${_screenFramePipeline.bufferLength} lastFrameAgo=${_screenHealth.lastFrameAgeDescription}',
      name: 'RemoteControl',
    );
    if (activeControllerSocket) {
      _controllerScreenSocket = null;
      _screenFramePipeline.reset();
      _stopScreenFrameWatchdog();
      _markUnexpectedControllerDisconnect('screen-done');
    }
    if (activeReceiverSocket) {
      _receiverScreenSocket = null;
      _screenFrameSender.detach(socket);
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _missedHeartbeatCount = 0;
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => _handleHeartbeatTick(),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _missedHeartbeatCount = 0;
  }

  void _handleHeartbeatReceived(HeartbeatMessage message) {
    _missedHeartbeatCount = 0;
    _markReceiverSessionActive();
    _markConnectionReady();
  }

  Future<void> _handleHeartbeatTick() async {
    if (_disconnectRequested || _state != RemoteControlState.connected) {
      return;
    }
    _missedHeartbeatCount += 1;
    final maxMissedHeartbeats = _mode == RemoteControlMode.receiver
        ? _receiverMaxMissedHeartbeats
        : _controllerMaxMissedHeartbeats;
    if (_missedHeartbeatCount >= maxMissedHeartbeats) {
      _handleHeartbeatTimeout();
      return;
    }
    if (_mode == RemoteControlMode.controller) {
      await _statusBridge.sendHeartbeat(
        controllerControlSocket: _controllerControlSocket,
      );
    }
  }

  void _handleHeartbeatTimeout() {
    if (_disconnectRequested) {
      return;
    }
    _logMessage(
      'Remote heartbeat timeout after $_missedHeartbeatCount missed checks',
    );
    _stopHeartbeat();
    if (_mode == RemoteControlMode.controller) {
      _markUnexpectedControllerDisconnect('heartbeat-timeout');
      unawaited(_resetControllerConnection(stopNative: true));
      return;
    }
    if (_mode == RemoteControlMode.receiver) {
      unawaited(stopAudioCapture());
      unawaited(_voiceCoordinator.close());
      unawaited(_showRemoteDisconnectOverlay('对方已断开远程连接。'));
      _receiverSessionActive = false;
      _receiverControlSocket?.destroy();
      _receiverControlSocket = null;
      _receiverScreenSocket?.destroy();
      _receiverScreenSocket = null;
      _screenFrameSender.reset();
      _updateState(RemoteControlState.disconnected);
      _scheduleReceiverAutoShutdown();
    }
  }

  void _scheduleReceiverAutoShutdown() {
    _receiverAutoShutdownTimer?.cancel();
    _receiverAutoShutdownTimer = Timer(_receiverAutoShutdownDelay, () {
      if (_mode != RemoteControlMode.receiver ||
          _state == RemoteControlState.connected) {
        return;
      }
      unawaited(shutdownReceiverHostResources());
    });
  }

  void _cancelReceiverAutoShutdown() {
    _receiverAutoShutdownTimer?.cancel();
    _receiverAutoShutdownTimer = null;
  }

  Future<void> shutdownReceiverHostResources() async {
    _cancelReceiverAutoShutdown();
    await disconnect();
    try {
      await EasyTierService().stopVpn();
    } catch (e) {
      developer.log(
        'Failed to stop EasyTier during receiver shutdown: $e',
        name: 'RemoteControl',
        error: e,
      );
    }
    if (_mode == RemoteControlMode.receiver) {
      _updateState(RemoteControlState.idle);
    }
  }

  Future<void> _sendAck(int messageId, bool success, [String? error]) async {
    await _statusBridge.sendAck(
      receiverControlSocket: _receiverControlSocket,
      messageId: messageId,
      success: success,
      error: error,
    );
  }

  void _updateState(RemoteControlState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
    developer.log('State changed to $newState', name: 'RemoteControl');
  }

  Future<void> disconnect() async {
    _disconnectRequested = true;
    _performanceMonitor.stopMonitoring();
    _stopScreenFrameWatchdog();
    _stopHeartbeat();
    _cancelReceiverAutoShutdown();
    await stopAudioCapture();
    await stopAudioPlayback();
    _controllerControlSocket?.destroy();
    _controllerControlSocket = null;
    _receiverControlSocket?.destroy();
    _receiverControlSocket = null;
    _controllerScreenSocket?.destroy();
    _controllerScreenSocket = null;
    _receiverScreenSocket?.destroy();
    _receiverScreenSocket = null;
    _screenFrameSender.reset();
    _controlServer?.close();
    _controlServer = null;
    _screenServer?.close();
    _screenServer = null;
    _screenFramePipeline.reset();
    _messageRouter.resetAll();
    _latestRemoteScreenInfo = null;
    _targetHost = null;
    _receiverSessionActive = false;

    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      developer.log(
        'Error stopping native service: $e',
        name: 'RemoteControl',
        error: e,
      );
    }

    _updateState(RemoteControlState.disconnected);
  }

  /// 导出性能监控日志
  String exportPerformanceLogs() {
    return _performanceMonitor.exportLogs();
  }

  /// 获取当前性能统计
  Map<String, dynamic> getCurrentPerformanceStats() {
    return _performanceMonitor.getCurrentStats();
  }

  void dispose() {
    _performanceMonitor.stopMonitoring();
    disconnect();
    _stateController.close();
    _messageController.close();
    _screenFrameController.close();
  }
}
