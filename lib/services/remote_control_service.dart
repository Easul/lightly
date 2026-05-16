import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../models/remote_control_config.dart';
import 'remote_control_command_helper.dart';
import 'remote_control_cleanup_helper.dart';
import 'remote_control_connection_helper.dart';
import 'remote_control_lifecycle_helper.dart';
import 'remote_control_protocol.dart';
import 'remote_control_screen_pipeline_helper.dart';
import 'remote_control_status_bridge.dart';
import 'remote_control_watchdog_controller.dart';
import 'screen_capture_manager.dart';
import 'audio_capture_service.dart';
import 'audio_playback_service.dart';
import 'opus_audio_service.dart';
import 'performance_monitor_service.dart';

enum RemoteControlMode { controller, receiver }

enum RemoteControlState { idle, connecting, connected, disconnected, error }

class RemoteControlService {
  static const MethodChannel _channel = MethodChannel('remote_control');
  static final RemoteControlService _instance =
      RemoteControlService._internal();
  factory RemoteControlService() => _instance;
  RemoteControlService._internal() {
    _setupMethodCallHandler();
  }

  RemoteControlMode _mode = RemoteControlMode.controller;
  RemoteControlState _state = RemoteControlState.idle;
  RemoteControlConfig? _config;
  String? _remoteHost;

  Socket? _controllerControlSocket;
  Socket? _receiverControlSocket;
  ServerSocket? _controlServer;
  Socket? _controllerScreenSocket;
  Socket? _receiverScreenSocket;
  ServerSocket? _screenServer;
  RawDatagramSocket? _audioSocket;

  final StreamController<RemoteControlState> _stateController =
      StreamController<RemoteControlState>.broadcast();
  final StreamController<ControlMessage> _messageController =
      StreamController<ControlMessage>.broadcast();
  final StreamController<ScreenFrame> _screenFrameController =
      StreamController<ScreenFrame>.broadcast();
  final StreamController<Uint8List> _audioFrameController =
      StreamController<Uint8List>.broadcast();

  final ScreenCaptureManager _screenCaptureManager = ScreenCaptureManager();
  final AudioCaptureService _audioCaptureService = AudioCaptureService();
  final AudioPlaybackService _audioPlaybackService = AudioPlaybackService();
  final OpusAudioService _opusService = OpusAudioService();
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
  final RemoteControlScreenPipelineHelper _screenPipelineHelper =
      const RemoteControlScreenPipelineHelper();
  final RemoteControlStatusBridge _statusBridge =
      const RemoteControlStatusBridge();
  final RemoteControlWatchdogController _watchdogController =
      RemoteControlWatchdogController();
  bool _useOpus = true; // 默认启用 Opus 编码

  static const Duration _receiverCaptureSuppressAfterPlayback = Duration(
    milliseconds: 180,
  );
  static const Duration _screenFrameStallThreshold = Duration(
    milliseconds: 700,
  );
  static const Duration _screenKeyFrameRequestCooldown = Duration(
    milliseconds: 1000,
  );
  static const Duration _screenRecoveryKeyFrameRetryCooldown = Duration(
    milliseconds: 450,
  );
  static const int _pcmAudioMarker = 0x00;
  static const int _opusAudioMarker = 0x01;
  static const int _maxPcmPayloadBytes = 640;
  static const int _maxOpusPayloadBytes = 256;
  static const int _latestFrameBatchThreshold = 3;

  final List<int> _screenDataBuffer = [];
  Uint8List? _latestRemoteSps;
  Uint8List? _latestRemotePps;
  Map<String, dynamic>? _latestRemoteScreenInfo;
  int _messageIdCounter = 0;
  Timer? _heartbeatTimer;
  StreamSubscription<Uint8List>? _audioCaptureSubscription;
  Completer<void>? _connectionReadyCompleter;
  final StringBuffer _controllerControlBuffer = StringBuffer();
  final StringBuffer _receiverControlBuffer = StringBuffer();
  String? _expectedAudioPeerHost;
  int? _expectedAudioPeerPort;
  DateTime? _lastIncomingAudioAt;

  // 视频流质量控制
  static const int _maxBitrate = 8000000;
  static const int _minBitrate = 500000;

  Stream<RemoteControlState> get stateStream => _stateController.stream;
  Stream<ControlMessage> get messageStream => _messageController.stream;
  Stream<ScreenFrame> get screenFrameStream => _screenFrameController.stream;
  Stream<Uint8List> get audioFrameStream => _audioFrameController.stream;
  ScreenCaptureManager get screenCaptureManager => _screenCaptureManager;
  AudioCaptureService get audioCaptureService => _audioCaptureService;
  AudioPlaybackService get audioPlaybackService => _audioPlaybackService;

  RemoteControlState get state => _state;
  RemoteControlMode get mode => _mode;
  RemoteControlConfig? get config => _config;
  bool get isConnected => _state == RemoteControlState.connected;
  Uint8List? get latestScreenSps =>
      _latestRemoteSps ?? _screenCaptureManager.spsData;
  Uint8List? get latestScreenPps =>
      _latestRemotePps ?? _screenCaptureManager.ppsData;
  Size? get latestRemoteScreenSize {
    final width = (_latestRemoteScreenInfo?['width'] as num?)?.toDouble();
    final height = (_latestRemoteScreenInfo?['height'] as num?)?.toDouble();
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width, height);
  }

  int _nextMessageId() => ++_messageIdCounter;

  void _markConnectionReady() {
    final completer = _connectionReadyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
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
          _watchdogController.markAwaitingRecoveryKeyFrame();

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

  void _sendScreenFrameOverTcp(ScreenFrame frame) {
    try {
      final header = ByteData(5);
      header.setUint8(0, frame.type == ScreenFrameType.keyFrame ? 0x02 : 0x03);
      header.setUint32(1, frame.data.length, Endian.big);
      _receiverScreenSocket!.add([
        ...header.buffer.asUint8List(),
        ...frame.data,
      ]);
    } catch (e) {
      developer.log('Failed to send screen frame: $e', name: 'RemoteControl');
    }
  }

  void _sendScreenConfigOverTcp(Uint8List sps, Uint8List pps) {
    try {
      final spsHeader = ByteData(5);
      spsHeader.setUint8(0, 0x01);
      spsHeader.setUint32(1, sps.length, Endian.big);
      _receiverScreenSocket!.add([...spsHeader.buffer.asUint8List(), ...sps]);

      final ppsHeader = ByteData(5);
      ppsHeader.setUint8(0, 0x01);
      ppsHeader.setUint32(1, pps.length, Endian.big);
      _receiverScreenSocket!.add([...ppsHeader.buffer.asUint8List(), ...pps]);
    } catch (e) {
      developer.log('Failed to send screen config: $e', name: 'RemoteControl');
    }
  }

  Future<RemoteControlPortConfig> startReceiver({
    RemoteControlConfig? config,
  }) async {
    _mode = RemoteControlMode.receiver;
    _config = config ?? await RemoteControlConfig.defaultConfig();
    final ports = _config!.ports;

    try {
      await _channel.invokeMethod('startReceiver', {
        'controlPort': ports.controlPort,
        'screenPort': ports.screenPort,
        'audioPort': ports.audioPort,
        'screenFps': _config!.screenFps,
        'screenBitrate': _config!.screenBitrate,
        'audioSampleRate': _config!.audioSampleRate,
        'audioBitrate': _config!.audioBitrate,
      });

      _controlServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        ports.controlPort,
      );
      _controlServer!.listen(_handleControlConnection);

      if (_config!.enableScreen) {
        _screenServer = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          ports.screenPort,
        );
        _screenServer!.listen(_handleScreenConnection);
      }

      if (_config!.enableAudio) {
        _audioSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          ports.audioPort,
        );
        _audioSocket!.listen(_handleAudioPacket);
        await startAudioPlayback(
          sampleRate: _config!.audioSampleRate,
          channels: 1,
        );
      }

      _updateState(RemoteControlState.idle);
      developer.log(
        'Receiver started on ports ${ports.controlPort}/${ports.screenPort}/${ports.audioPort}',
        name: 'RemoteControl',
      );
      return ports;
    } catch (e) {
      await _rollbackReceiverStartup();
      _updateState(RemoteControlState.error);
      developer.log(
        'Failed to start receiver: $e',
        name: 'RemoteControl',
        error: e,
      );
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
    _remoteHost = host;
    _config = RemoteControlConfig(ports: ports);
    _expectedAudioPeerHost = host;
    _expectedAudioPeerPort = ports.audioPort;

    // 记录设备发现路径
    _performanceMonitor.recordDiscoveryPath(
      selectedHost: host,
      availableHosts: availableHosts.isNotEmpty ? availableHosts : [host],
      selectionDelayMs: discoveryDelayMs,
    );
    _performanceMonitor.startMonitoring();

    _updateState(RemoteControlState.connecting);

    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      var nativeControllerStarted = false;
      try {
        _connectionReadyCompleter = Completer<void>();
        _screenDataBuffer.clear();

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
          onAudioPacket: _handleAudioPacket,
          startAudioPlayback: startAudioPlayback,
          sendAudioPortStatus: _sendAudioPortStatus,
        );
        _controllerControlSocket = connection.controlSocket;
        _controllerScreenSocket = connection.screenSocket;
        _audioSocket = connection.audioSocket;

        await _channel.invokeMethod('startController', {
          'host': host,
          'audioPort': ports.audioPort,
        });
        nativeControllerStarted = true;

        _startScreenFrameWatchdog();
        _startHeartbeat();
        await _connectionReadyCompleter!.future.timeout(
          const Duration(seconds: 2),
        );
        _updateState(RemoteControlState.connected);
        developer.log('Connected to $host', name: 'RemoteControl');
        return;
      } catch (e) {
        lastError = e;
        developer.log(
          'Connect attempt ${attempt + 1} failed: $e',
          name: 'RemoteControl',
          error: e,
        );
        await _resetControllerConnection(stopNative: nativeControllerStarted);
        if (attempt < 3) {
          await Future<void>.delayed(
            Duration(milliseconds: 350 * (attempt + 1)),
          );
        }
      } finally {
        _connectionReadyCompleter = null;
      }
    }

    _updateState(RemoteControlState.error);
    throw lastError ?? Exception('连接失败');
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

  Future<void> _resetControllerConnection({required bool stopNative}) async {
    developer.log(
      'Resetting controller connection: stopNative=$stopNative state=$_state screenSocket=${_controllerScreenSocket != null} controlSocket=${_controllerControlSocket != null} audioSocket=${_audioSocket != null} buffer=${_screenDataBuffer.length}',
      name: 'RemoteControl',
    );
    await _cleanupHelper.resetControllerConnection(
      stopNative: stopNative,
      controllerControlSocket: _controllerControlSocket,
      controllerScreenSocket: _controllerScreenSocket,
      audioSocket: _audioSocket,
      screenDataBuffer: _screenDataBuffer,
      controllerControlBuffer: _controllerControlBuffer,
      stopScreenFrameWatchdog: _stopScreenFrameWatchdog,
      stopHeartbeat: _stopHeartbeat,
      stopAudioPlayback: stopAudioPlayback,
      stopNativeService: () => _channel.invokeMethod('stop'),
    );
    _controllerControlSocket = null;
    _controllerScreenSocket = null;
    _audioSocket = null;
    _expectedAudioPeerPort = _mode == RemoteControlMode.controller
        ? _config?.ports.audioPort
        : null;
  }

  Future<void> _rollbackReceiverStartup() async {
    await _cleanupHelper.rollbackReceiverStartup(
      receiverControlSocket: _receiverControlSocket,
      receiverScreenSocket: _receiverScreenSocket,
      audioSocket: _audioSocket,
      controlServer: _controlServer,
      screenServer: _screenServer,
      stopScreenFrameWatchdog: _stopScreenFrameWatchdog,
      stopAudioCapture: stopAudioCapture,
      stopAudioPlayback: stopAudioPlayback,
      stopNativeService: () => _channel.invokeMethod('stop'),
    );
    _receiverControlSocket = null;
    _receiverScreenSocket = null;
    _audioSocket = null;
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

  Future<void> sendAudioFrame(Uint8List opusData, int sequence) async {
    if (_audioSocket == null || _remoteHost == null) return;
    final destinationPort = switch (_mode) {
      RemoteControlMode.controller => _config?.ports.audioPort,
      RemoteControlMode.receiver => _expectedAudioPeerPort,
    };
    if (destinationPort == null) return;
    final header = ByteData(6);
    header.setUint16(0, sequence, Endian.big);
    header.setUint32(
      2,
      DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF,
      Endian.big,
    );
    final packet = Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...opusData,
    ]);
    _audioSocket!.send(packet, InternetAddress(_remoteHost!), destinationPort);
  }

  Future<void> _sendAudioPortStatus(int port) async {
    await _statusBridge.sendAudioPortStatus(
      controllerControlSocket: _controllerControlSocket,
      port: port,
    );
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
        'Forwarding key frame request over control channel: state=$_state screenSocket=${_controllerScreenSocket != null} lastFrameAgo=${_watchdogController.lastScreenFrameTime == null ? 'never' : '${DateTime.now().difference(_watchdogController.lastScreenFrameTime!).inMilliseconds}ms'} buffer=${_screenDataBuffer.length}',
        name: 'RemoteControl',
      );
      final message = StatusMessage.requestKeyFrame();
      controllerSocket.add(
        utf8.encode('${RemoteControlCodec.encode(message)}\n'),
      );
      _watchdogController.recordKeyFrameRequest(requestedAt);
      return;
    }

    try {
      developer.log(
        'Issuing native key frame request: mode=$_mode state=$_state buffer=${_screenDataBuffer.length}',
        name: 'RemoteControl',
      );
      await _channel.invokeMethod('requestKeyFrame');
      _watchdogController.recordKeyFrameRequest(requestedAt);
    } catch (e) {
      developer.log(
        'Failed to request key frame: $e',
        name: 'RemoteControl',
        error: e,
      );
    }
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
    try {
      await _audioCaptureSubscription?.cancel();
      await _audioCaptureService.initialize(
        sampleRate: sampleRate,
        channels: channels,
      );

      // 初始化 Opus 如果启用
      if (_useOpus) {
        try {
          await _opusService.initialize();
          developer.log('Opus encoding enabled', name: 'RemoteControl');
        } catch (e) {
          developer.log(
            'Failed to initialize Opus, falling back to PCM: $e',
            name: 'RemoteControl',
          );
          _useOpus = false;
        }
      }

      _audioCaptureSubscription = _audioCaptureService.frameStream.listen((
        pcmData,
      ) {
        if (_shouldSuppressOutgoingCapturedAudio()) {
          return;
        }
        if (_useOpus) {
          // Opus 编码: 16kHz 采样率下 20ms 帧 = 640 bytes PCM -> ~60 bytes Opus
          final encoded = _opusService.encodeFrame(pcmData);
          if (encoded != null) {
            final packet = Uint8List(encoded.length + 1);
            packet[0] = _opusAudioMarker;
            packet.setAll(1, encoded);
            sendAudioFrame(packet, _audioCaptureService.sequence);
          } else {
            final packet = Uint8List(pcmData.length + 1);
            packet[0] = _pcmAudioMarker;
            packet.setAll(1, pcmData);
            sendAudioFrame(packet, _audioCaptureService.sequence);
          }
        } else {
          final packet = Uint8List(pcmData.length + 1);
          packet[0] = _pcmAudioMarker;
          packet.setAll(1, pcmData);
          sendAudioFrame(packet, _audioCaptureService.sequence);
        }
      });
      return await _audioCaptureService.start();
    } catch (e) {
      developer.log(
        'Failed to start audio capture: $e',
        name: 'RemoteControl',
        error: e,
      );
      return false;
    }
  }

  Future<void> stopAudioCapture() async {
    await _audioCaptureSubscription?.cancel();
    _audioCaptureSubscription = null;
    await _audioCaptureService.stop();
  }

  Future<void> startAudioPlayback({
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    try {
      if (_audioPlaybackService.isPlaying) {
        return;
      }
      try {
        await _opusService.initialize();
      } catch (e) {
        developer.log(
          'Opus decode unavailable, playback will accept PCM only: $e',
          name: 'RemoteControl',
        );
      }
      await _audioPlaybackService.initialize(
        sampleRate: sampleRate,
        channels: channels,
      );
      await _audioPlaybackService.start();
    } catch (e) {
      developer.log(
        'Failed to start audio playback: $e',
        name: 'RemoteControl',
        error: e,
      );
    }
  }

  Future<void> stopAudioPlayback() async {
    await _audioPlaybackService.stop();
  }

  void _handleControlConnection(Socket client) {
    developer.log(
      'Control client connected: ${client.remoteAddress}',
      name: 'RemoteControl',
    );
    _receiverControlSocket = client;
    _remoteHost = client.remoteAddress.address;
    _expectedAudioPeerHost = client.remoteAddress.address;
    _expectedAudioPeerPort = null;
    _updateState(RemoteControlState.connected);
    unawaited(_sendPortConfigStatus());
    unawaited(_sendScreenInfoStatus());

    _lifecycleHelper.attachReceiverControlClient(
      client: client,
      onData: _handleReceiverControlData,
      onError: (error) =>
          developer.log('Control client error: $error', name: 'RemoteControl'),
      onDone: () {
        developer.log('Control client disconnected', name: 'RemoteControl');
        unawaited(stopAudioCapture());
        _receiverControlSocket = null;
        _expectedAudioPeerPort = null;
        _updateState(RemoteControlState.disconnected);
        _stopScreenFrameWatchdog();
        _stopHeartbeat();
      },
    );
  }

  void _handleScreenConnection(Socket client) {
    developer.log(
      'Screen client connected: ${client.remoteAddress}',
      name: 'RemoteControl',
    );
    _receiverScreenSocket = client;
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
    _watchdogController.recordScreenChunk(
      data: data,
      bufferedBefore: _screenDataBuffer.length,
      log: (message) => developer.log(message, name: 'RemoteControl'),
    );

    _screenDataBuffer.addAll(data);

    final parseResult = _screenPipelineHelper.parseScreenDataBuffer(
      screenDataBuffer: _screenDataBuffer,
      awaitingRecoveryKeyFrame: _watchdogController.awaitingRecoveryKeyFrame,
    );
    if (parseResult.latestSps != null) {
      _latestRemoteSps = parseResult.latestSps;
    }
    if (parseResult.latestPps != null) {
      _latestRemotePps = parseResult.latestPps;
    }
    _watchdogController.markAwaitingRecoveryKeyFrame(
      parseResult.awaitingRecoveryKeyFrame,
    );

    _processParsedScreenFrames(parseResult.parsedFrames);
  }

  void _processParsedScreenFrames(List<ScreenFrame> parsedFrames) {
    if (parsedFrames.isEmpty) {
      return;
    }

    final framesToEmit = _screenPipelineHelper.coalesceLatestScreenFrames(
      parsedFrames,
      latestFrameBatchThreshold: _latestFrameBatchThreshold,
      awaitingRecoveryKeyFrame: _watchdogController.awaitingRecoveryKeyFrame,
    );
    if (parsedFrames.length != framesToEmit.length) {
      developer.log(
        'Dropping stale parsed screen frames: parsed=${parsedFrames.length} kept=${framesToEmit.length} buffered=${_screenDataBuffer.length}',
        name: 'RemoteControl',
      );
    }

    for (final frame in framesToEmit) {
      _watchdogController.recordParsedFrame(
        frame: frame,
        remainingBuffer: _screenDataBuffer.length,
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
    final newBitrate = _watchdogController.adjustBitrateIfNeeded(
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
    _watchdogController.startScreenFrameWatchdog(
      log: (message) => developer.log(message, name: 'RemoteControl'),
      onTick: _checkScreenFrameHealth,
      screenFrameStallThreshold: _screenFrameStallThreshold,
      screenKeyFrameRequestCooldown: _screenKeyFrameRequestCooldown,
      screenRecoveryKeyFrameRetryCooldown: _screenRecoveryKeyFrameRetryCooldown,
    );
  }

  void _stopScreenFrameWatchdog() {
    _watchdogController.stopScreenFrameWatchdog(
      log: (message) => developer.log(message, name: 'RemoteControl'),
      bufferLength: _screenDataBuffer.length,
    );
  }

  void _checkScreenFrameHealth() {
    if (_mode != RemoteControlMode.controller ||
        _state != RemoteControlState.connected ||
        _controllerScreenSocket == null ||
        _config?.enableScreen != true) {
      return;
    }

    if (_watchdogController.checkScreenFrameHealth(
      screenRecoveryKeyFrameRetryCooldown: _screenRecoveryKeyFrameRetryCooldown,
      screenKeyFrameRequestCooldown: _screenKeyFrameRequestCooldown,
      screenFrameStallThreshold: _screenFrameStallThreshold,
      screenDataBufferLength: _screenDataBuffer.length,
      log: (message) => developer.log(message, name: 'RemoteControl'),
    )) {
      unawaited(requestKeyFrame());
    }
  }

  void _handleAudioPacket(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      while (true) {
        final datagram = _audioSocket!.receive();
        if (datagram == null) return;
        final remoteHost = _expectedAudioPeerHost;
        if (remoteHost != null && datagram.address.address != remoteHost) {
          continue;
        }
        final expectedPort = _expectedAudioPeerPort;
        if (expectedPort != null && datagram.port != expectedPort) {
          continue;
        }
        _expectedAudioPeerPort ??= datagram.port;
        final packet = _decodeAudioPacket(datagram.data);
        final decodedAudio = _decodeIncomingAudioPayload(packet.data);
        if (decodedAudio == null) {
          continue;
        }
        _lastIncomingAudioAt = DateTime.now();

        _performanceMonitor.recordAudioPacket(
          packetSize: datagram.data.length,
          sequence: packet.sequence,
        );

        _audioFrameController.add(decodedAudio);
        if (_audioPlaybackService.isPlaying) {
          _audioPlaybackService.feedFrame(
            decodedAudio,
            packet.sequence,
            packet.timestamp,
          );
        }
      }
    }
  }

  ({Uint8List data, int sequence, int timestamp}) _decodeAudioPacket(
    Uint8List packet,
  ) {
    if (packet.length < 6) {
      return (data: packet, sequence: 0, timestamp: 0);
    }

    final header = ByteData.sublistView(packet, 0, 6);
    final sequence = header.getUint16(0, Endian.big);
    final timestamp = header.getUint32(2, Endian.big);
    return (
      data: Uint8List.sublistView(packet, 6),
      sequence: sequence,
      timestamp: timestamp,
    );
  }

  Uint8List? _decodeIncomingAudioPayload(Uint8List payload) {
    if (payload.isEmpty) {
      return null;
    }

    final marker = payload[0];
    if (marker == _opusAudioMarker) {
      final opusPayload = Uint8List.sublistView(payload, 1);
      if (opusPayload.isEmpty || opusPayload.length > _maxOpusPayloadBytes) {
        developer.log(
          'Dropping audio packet: invalid Opus payload length=${opusPayload.length}',
          name: 'RemoteControl',
        );
        return null;
      }
      final decoded = _opusService.decodeFrame(opusPayload);
      if (decoded == null) {
        developer.log(
          'Dropping audio packet: failed to decode Opus payload',
          name: 'RemoteControl',
        );
      }
      return decoded;
    }

    if (marker == _pcmAudioMarker) {
      final pcmPayload = Uint8List.sublistView(payload, 1);
      if (pcmPayload.isEmpty || pcmPayload.length > _maxPcmPayloadBytes) {
        developer.log(
          'Dropping audio packet: invalid PCM payload length=${pcmPayload.length}',
          name: 'RemoteControl',
        );
        return null;
      }
      return pcmPayload;
    }

    // Backward compatibility for older PCM packets without codec marker.
    return payload;
  }

  bool _shouldSuppressOutgoingCapturedAudio() {
    if (_mode == RemoteControlMode.controller) {
      return false;
    }
    final lastIncomingAudioAt = _lastIncomingAudioAt;
    if (lastIncomingAudioAt == null || !_audioPlaybackService.isPlaying) {
      return false;
    }
    return DateTime.now().difference(lastIncomingAudioAt) <=
        _receiverCaptureSuppressAfterPlayback;
  }

  void _handleControlData(Uint8List data) {
    final messages = _commandHelper.decodeBufferedMessages(
      _controllerControlBuffer,
      data,
    );
    for (final message in messages) {
      _recordStatusMessage(message);
      _messageController.add(message);
    }
  }

  void _recordStatusMessage(ControlMessage message) {
    _statusBridge.recordStatusMessage(
      message: message,
      onScreenInfo: (info) => _latestRemoteScreenInfo = info,
      markConnectionReady: _markConnectionReady,
      onAudioPort: (port) => _expectedAudioPeerPort = port,
      onPortConfig: (ports) {
        _config = RemoteControlConfig(
          ports: ports,
          enableAudio: _config?.enableAudio ?? true,
          enableScreen: _config?.enableScreen ?? true,
          screenFps: _config?.screenFps ?? 15,
          screenBitrate: _config?.screenBitrate ?? 2000000,
          audioSampleRate: _config?.audioSampleRate ?? 16000,
          audioBitrate: _config?.audioBitrate ?? 24000,
        );
      },
    );
  }

  void _handleReceiverControlData(Uint8List data) {
    final commands = _commandHelper.decodeBufferedLines(
      _receiverControlBuffer,
      data,
    );
    for (final command in commands) {
      _commandHelper.dispatchReceiverCommand(
        command,
        channel: _channel,
        minBitrate: _minBitrate,
        maxBitrate: _maxBitrate,
        recordStatusMessage: _recordStatusMessage,
        emitMessage: _messageController.add,
        requestKeyFrame: requestKeyFrame,
        updateBitrate: updateBitrate,
        sendAck: _sendAck,
        log: (message, {error}) =>
            developer.log(message, name: 'RemoteControl', error: error),
      );
    }
  }

  void _handleControlError(dynamic error) {
    developer.log('Control channel error: $error', name: 'RemoteControl');
    unawaited(_resetControllerConnection(stopNative: true));
    _updateState(RemoteControlState.error);
  }

  void _handleControlDone() {
    developer.log('Control channel closed', name: 'RemoteControl');
    unawaited(_resetControllerConnection(stopNative: true));
    _updateState(RemoteControlState.disconnected);
    _stopScreenFrameWatchdog();
    _stopHeartbeat();
  }

  void _handleScreenError(
    dynamic error, {
    required Socket socket,
    required RemoteControlMode mode,
  }) {
    final activeControllerSocket = identical(_controllerScreenSocket, socket);
    final activeReceiverSocket = identical(_receiverScreenSocket, socket);
    developer.log(
      'Screen channel error: $error state=$_state mode=$_mode sourceMode=$mode activeControllerSocket=$activeControllerSocket activeReceiverSocket=$activeReceiverSocket buffer=${_screenDataBuffer.length} lastFrameAgo=${_watchdogController.lastScreenFrameTime == null ? 'never' : '${DateTime.now().difference(_watchdogController.lastScreenFrameTime!).inMilliseconds}ms'}',
      name: 'RemoteControl',
    );
    if (activeControllerSocket) {
      _controllerScreenSocket = null;
      _screenDataBuffer.clear();
      _stopScreenFrameWatchdog();
    }
    if (activeReceiverSocket) {
      _receiverScreenSocket = null;
    }
  }

  void _handleScreenDone({
    required Socket socket,
    required RemoteControlMode mode,
  }) {
    final activeControllerSocket = identical(_controllerScreenSocket, socket);
    final activeReceiverSocket = identical(_receiverScreenSocket, socket);
    developer.log(
      'Screen channel closed: state=$_state mode=$_mode sourceMode=$mode activeControllerSocket=$activeControllerSocket activeReceiverSocket=$activeReceiverSocket buffer=${_screenDataBuffer.length} lastFrameAgo=${_watchdogController.lastScreenFrameTime == null ? 'never' : '${DateTime.now().difference(_watchdogController.lastScreenFrameTime!).inMilliseconds}ms'}',
      name: 'RemoteControl',
    );
    if (activeControllerSocket) {
      _controllerScreenSocket = null;
      _screenDataBuffer.clear();
      _stopScreenFrameWatchdog();
    }
    if (activeReceiverSocket) {
      _receiverScreenSocket = null;
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _sendHeartbeat(),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _sendHeartbeat() async {
    await _statusBridge.sendHeartbeat(
      controllerControlSocket: _controllerControlSocket,
    );
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
    _performanceMonitor.stopMonitoring();
    _stopScreenFrameWatchdog();
    _stopHeartbeat();
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
    _audioSocket?.close();
    _audioSocket = null;
    _controlServer?.close();
    _controlServer = null;
    _screenServer?.close();
    _screenServer = null;
    _screenDataBuffer.clear();
    _controllerControlBuffer.clear();
    _receiverControlBuffer.clear();
    _latestRemoteSps = null;
    _latestRemotePps = null;
    _latestRemoteScreenInfo = null;
    _lastIncomingAudioAt = null;
    _connectionReadyCompleter = null;
    _expectedAudioPeerHost = null;
    _expectedAudioPeerPort = null;

    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      developer.log(
        'Error stopping native service: $e',
        name: 'RemoteControl',
        error: e,
      );
    }

    _remoteHost = null;
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
    _audioFrameController.close();
  }
}
