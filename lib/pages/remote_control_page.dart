import 'dart:async';
import 'package:flutter/material.dart';
import '../core/logging/runtime_logger.dart';
import '../features/remote_control/application/remote_control_page_runtime.dart';
import '../features/remote_control/domain/remote_control_config.dart';
import '../features/remote_control/domain/remote_control_runtime.dart';
import '../features/remote_control/presentation/widgets/remote_control_disconnect_dialog.dart';
import '../features/remote_control/presentation/widgets/remote_control_setup_sections.dart';
import 'remote_control_session_page.dart';
import 'remote_control_page_connection_helper.dart';
import 'remote_control_page_port_config_helper.dart';
import 'remote_control_page_receiver_helper.dart';
import '../features/remote_control/domain/remote_control_protocol.dart'
    as protocol;

part 'remote_control_page_peer_actions.dart';
part 'remote_control_page_receiver_actions.dart';

class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({
    super.key,
    required this.service,
    required this.runtimeCoordinator,
    required this.permissionRuntime,
    required this.runtimeLogger,
    required this.showMessage,
    required this.navigatorKey,
  });

  final RemoteControlPresentationRuntime service;
  final RemoteControlPageRuntime runtimeCoordinator;
  final RemoteControlPermissionRuntime permissionRuntime;
  final RuntimeLogger runtimeLogger;
  final Future<void> Function(String message) showMessage;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

@visibleForTesting
class RemoteControlPageStateSnapshot {
  const RemoteControlPageStateSnapshot({
    required this.selectedMode,
    required this.portConfig,
    required this.isConnecting,
    required this.isReceiverAudioEnabled,
    required this.isReceiverRunning,
    required this.useReceiverNoTunMode,
    required this.hadConnectedSession,
  });

  final RemoteControlMode selectedMode;
  final RemoteControlPortConfig? portConfig;
  final bool isConnecting;
  final bool isReceiverAudioEnabled;
  final bool isReceiverRunning;
  final bool useReceiverNoTunMode;
  final bool hadConnectedSession;

  factory RemoteControlPageStateSnapshot.fromValues({
    required RemoteControlMode currentSelectedMode,
    required RemoteControlMode serviceMode,
    required RemoteControlState serviceState,
    required RemoteControlPortConfig? servicePorts,
    required bool isReceiverHostRunning,
    required bool isReceiverNoTunMode,
    required bool isLocalAudioEnabled,
  }) {
    final receiverMode = serviceMode == RemoteControlMode.receiver;
    return RemoteControlPageStateSnapshot(
      selectedMode: receiverMode
          ? RemoteControlMode.receiver
          : currentSelectedMode,
      portConfig: servicePorts,
      isConnecting: serviceState == RemoteControlState.connecting,
      isReceiverAudioEnabled: isLocalAudioEnabled,
      isReceiverRunning: isReceiverHostRunning,
      useReceiverNoTunMode: receiverMode && isReceiverNoTunMode,
      hadConnectedSession:
          isReceiverHostRunning && serviceState == RemoteControlState.connected,
    );
  }

  factory RemoteControlPageStateSnapshot.fromService({
    required RemoteControlMode currentSelectedMode,
    required RemoteControlPresentationRuntime service,
  }) {
    return RemoteControlPageStateSnapshot.fromValues(
      currentSelectedMode: currentSelectedMode,
      serviceMode: service.mode,
      serviceState: service.state,
      servicePorts: service.config?.ports,
      isReceiverHostRunning: service.isReceiverHostRunning,
      isReceiverNoTunMode: service.isReceiverNoTunMode,
      isLocalAudioEnabled: service.isLocalAudioEnabled,
    );
  }
}

@visibleForTesting
bool resolveReceiverNoTunMode({
  required bool receiverNoTunMode,
  required bool p2pNoTunMode,
}) {
  return p2pNoTunMode || receiverNoTunMode;
}

class _RemoteControlPageState extends State<RemoteControlPage> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _controlPortController = TextEditingController();
  final TextEditingController _screenPortController = TextEditingController();
  final RemoteControlPageConnectionHelper _connectionHelper =
      const RemoteControlPageConnectionHelper();
  final RemoteControlPagePortConfigHelper _portConfigHelper =
      const RemoteControlPagePortConfigHelper();
  final RemoteControlPageReceiverHelper _receiverHelper =
      const RemoteControlPageReceiverHelper();

  RemoteControlMode _selectedMode = RemoteControlMode.controller;
  RemoteControlPortConfig? _portConfig;
  bool _isConnecting = false;
  bool _isReceiverAudioEnabled = false;
  String? _errorMessage;
  List<Map<String, String>> _peers = [];
  bool _isLoadingPeers = false;
  bool _useInternalProxy = false;
  bool _isProxyRunning = false;
  bool _isReceiverRunning = false;
  bool _useReceiverNoTunMode = false;
  Timer? _peerRefreshTimer;
  bool _hadConnectedSession = false;
  bool _disconnectDialogVisible = false;

  late StreamSubscription<RemoteControlState> _stateSubscription;
  late StreamSubscription<protocol.ControlMessage> _messageSubscription;
  StreamSubscription<bool>? _proxyStateSubscription;

  RemoteControlPresentationRuntime get _service => widget.service;
  RemoteControlPageRuntime get _runtimeCoordinator => widget.runtimeCoordinator;

  void _updateState(VoidCallback update) {
    setState(update);
  }

  void _showToast(String message) {
    unawaited(widget.showMessage(message));
  }

  @override
  void initState() {
    super.initState();
    _stateSubscription = _service.stateStream.listen(_handleStateChange);
    _messageSubscription = _service.messageStream.listen(_handleMessage);
    _syncReceiverStateFromService();
    _applyPortConfigToInputs(_portConfig);
    _loadRuntimeState();
    _loadPeers();
    _peerRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_loadPeers(showLoading: false));
    });
  }

  void _syncReceiverStateFromService() {
    final snapshot = RemoteControlPageStateSnapshot.fromService(
      currentSelectedMode: _selectedMode,
      service: _service,
    );
    _selectedMode = snapshot.selectedMode;
    _portConfig = snapshot.portConfig;
    _isConnecting = snapshot.isConnecting;
    _isReceiverAudioEnabled = snapshot.isReceiverAudioEnabled;
    _isReceiverRunning = snapshot.isReceiverRunning;
    _useReceiverNoTunMode = snapshot.useReceiverNoTunMode;
    _syncReceiverNoTunModeFromP2p();
    _hadConnectedSession = snapshot.hadConnectedSession;
  }

  void _syncReceiverNoTunModeFromP2p() {
    _useReceiverNoTunMode = resolveReceiverNoTunMode(
      receiverNoTunMode: _useReceiverNoTunMode,
      p2pNoTunMode: _runtimeCoordinator.isEasyTierNoTunMode,
    );
  }

  Future<void> _loadRuntimeState() async {
    final state = await _runtimeCoordinator.initialize();
    if (mounted) {
      setState(() {
        _isProxyRunning = state.isProxyRunning;
      });
    }
    _proxyStateSubscription = _runtimeCoordinator.proxyRunningStream.listen((
      isRunning,
    ) {
      if (mounted) {
        setState(() {
          _isProxyRunning = isRunning;
        });
      }
    });
  }

  @override
  void dispose() {
    _peerRefreshTimer?.cancel();
    _proxyStateSubscription?.cancel();
    _stateSubscription.cancel();
    _messageSubscription.cancel();
    super.dispose();
  }

  void _handleStateChange(RemoteControlState state) {
    if (!mounted) return;
    final shouldShowDisconnectDialog =
        _hadConnectedSession &&
        !_service.isLocalDisconnectRequested &&
        (state == RemoteControlState.disconnected ||
            state == RemoteControlState.error);
    final shouldRefreshPeers = state == RemoteControlState.connected;
    setState(() {
      _isConnecting = state == RemoteControlState.connecting;
      _isReceiverAudioEnabled = _service.isLocalAudioEnabled;
      if (state == RemoteControlState.connected) {
        _hadConnectedSession = true;
        _errorMessage = null;
      } else if (state == RemoteControlState.error) {
        _errorMessage = '连接失败';
      } else if (state == RemoteControlState.disconnected) {
        _errorMessage = null;
      } else if (state == RemoteControlState.idle &&
          _service.mode == RemoteControlMode.receiver &&
          !_service.isReceiverHostRunning) {
        _isReceiverRunning = false;
        _isReceiverAudioEnabled = false;
        _portConfig = null;
      }
    });
    if (shouldRefreshPeers) {
      unawaited(_loadPeers(showLoading: false));
    }
    if (shouldShowDisconnectDialog &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_showDisconnectDialog(state));
    }
  }

  Future<void> _showDisconnectDialog(RemoteControlState state) async {
    if (_disconnectDialogVisible || !mounted) {
      return;
    }
    _disconnectDialogVisible = true;
    await showRemoteDisconnectDialog(
      context: context,
      message: state == RemoteControlState.error
          ? '对方连接异常中断，请检查网络或对端状态。'
          : '对方已断开远程连接。',
    );
    _disconnectDialogVisible = false;
  }

  void _handleMessage(protocol.ControlMessage message) {
    if (message is! protocol.StatusMessage) {
      return;
    }
    if (message.action == 'receiver_microphone_status') {
      final enabled = message.data['enabled'] == true;
      if (mounted && _isReceiverAudioEnabled != enabled) {
        setState(() => _isReceiverAudioEnabled = enabled);
      }
    }
  }

  Future<void> _toggleReceiverMic() async {
    if (_service.mode != RemoteControlMode.receiver) {
      return;
    }
    if (_service.state != RemoteControlState.connected) {
      if (mounted) {
        _showToast('请先等待主控端连接后再切换麦克风');
      }
      return;
    }
    if (!_service.isVoiceEnabled) {
      _showToast('非 VPN 模式会禁用若轻实时通话');
      return;
    }

    if (_isReceiverAudioEnabled) {
      await _service.stopAudioCapture();
      if (!mounted) return;
      setState(() => _isReceiverAudioEnabled = false);
      return;
    }

    final success = await _service.startAudioCapture();
    if (!mounted) return;
    if (success) {
      setState(() => _isReceiverAudioEnabled = true);
    } else {
      _showToast('无法启动麦克风，请检查权限');
    }
  }

  Future<void> _connectToReceiver() async {
    final host = _normalizeHost(_hostController.text.trim());
    if (host.isEmpty) {
      setState(() => _errorMessage = '请输入被控端地址');
      return;
    }

    setState(() {
      _hostController.text = host;
      _isConnecting = true;
      _errorMessage = null;
      _hadConnectedSession = false;
    });

    final noTunControllerMode = _runtimeCoordinator.isEasyTierNoTunMode;
    final candidatePorts = _buildCandidatePorts();
    final noTunProxyPort = _runtimeCoordinator.activeNoTunSocksPort;
    if (noTunControllerMode && noTunProxyPort == null) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _errorMessage = 'P2P 非 VPN 代理端口不可用';
      });
      return;
    }

    int? proxyPort;
    try {
      proxyPort = noTunControllerMode
          ? noTunProxyPort
          : await _runtimeCoordinator.ensureInternalProxyReady(
              useInternalProxy: _useInternalProxy,
            );
    } on RemoteControlPageRuntimeException catch (error) {
      if (mounted) {
        _showToast(error.message);
      }
      setState(() => _isConnecting = false);
      return;
    }

    final discoveredPorts = await _connectionHelper.discoverReceiverPorts(
      service: _service,
      host: host,
      useInternalProxy: noTunControllerMode || _useInternalProxy,
      proxyPort: proxyPort,
    );
    if (discoveredPorts != null && mounted) {
      setState(() {
        _portConfig = discoveredPorts;
      });
      _applyPortConfigToInputs(discoveredPorts);
    }
    final portsToTry = discoveredPorts != null
        ? <RemoteControlPortConfig>[discoveredPorts]
        : candidatePorts;

    Object? lastError;
    for (final ports in portsToTry) {
      try {
        await _service.connectToReceiver(
          host,
          ports,
          useProxy: noTunControllerMode || _useInternalProxy,
          proxyPort: proxyPort,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _isConnecting = false;
          _portConfig = ports;
        });
        _applyPortConfigToInputs(_portConfig);
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RemoteControlSessionPage(
              service: _service,
              remoteHost: host,
              shutdownAll: _runtimeCoordinator.shutdownAll,
              showMessage: widget.showMessage,
              navigatorKey: widget.navigatorKey,
            ),
          ),
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }

    setState(() {
      _isConnecting = false;
      _errorMessage = _connectionHelper.buildConnectErrorMessage(lastError);
    });
  }

  List<RemoteControlPortConfig> _buildCandidatePorts() {
    return _portConfigHelper.buildCandidatePorts(_portConfig);
  }

  String _normalizeHost(String host) {
    return _portConfigHelper.normalizeHost(host);
  }

  void _applyPortConfigToInputs(RemoteControlPortConfig? ports) {
    _portConfigHelper.applyPortConfigToInputs(
      controlPortController: _controlPortController,
      screenPortController: _screenPortController,
      ports: ports,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('远程控制')),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewPaddingOf(context).bottom + 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildModeSelector(),
            const SizedBox(height: 24),
            if (_selectedMode == RemoteControlMode.receiver)
              _buildReceiverSection()
            else
              _buildControllerSection(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              RemoteControlErrorBanner(message: _errorMessage!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return RemoteControlModeSelectorSection(
      selectedMode: _selectedMode,
      onReceiverTap: () => setState(() {
        _selectedMode = RemoteControlMode.receiver;
        _errorMessage = null;
      }),
      onControllerTap: () => setState(() {
        _selectedMode = RemoteControlMode.controller;
        _portConfig = null;
        _applyPortConfigToInputs(null);
        _errorMessage = null;
      }),
    );
  }

  Widget _buildReceiverSection() {
    final effectiveNoTunMode = resolveReceiverNoTunMode(
      receiverNoTunMode: _useReceiverNoTunMode,
      p2pNoTunMode: _runtimeCoordinator.isEasyTierNoTunMode,
    );
    return RemoteControlReceiverSection(
      portConfig: _portConfig,
      isReceiverAudioEnabled: _isReceiverAudioEnabled,
      state: _service.state,
      isConnecting: _isConnecting,
      isReceiverRunning: _isReceiverRunning,
      useNoTunMode: effectiveNoTunMode,
      onUseNoTunModeChanged: (value) {
        setState(() => _useReceiverNoTunMode = value);
      },
      onToggleReceiverMic: _toggleReceiverMic,
      onToggleReceiver: _toggleReceiver,
    );
  }

  Widget _buildControllerSection() {
    return RemoteControlControllerSection(
      peers: _peers,
      isEasyTierRunning: _runtimeCoordinator.isEasyTierRunning,
      isEasyTierNoTunMode: _runtimeCoordinator.isEasyTierNoTunMode,
      isLoadingPeers: _isLoadingPeers,
      hostController: _hostController,
      controlPortController: _controlPortController,
      screenPortController: _screenPortController,
      portConfig: _portConfig,
      isConnecting: _isConnecting,
      useInternalProxy: _useInternalProxy,
      isProxyRunning: _isProxyRunning,
      onReloadPeers: _loadPeers,
      onSelectPeer: _selectPeer,
      onControlPortChanged: (value) {
        setState(() {
          _portConfig = _portConfigHelper.updateControlPort(_portConfig, value);
        });
      },
      onScreenPortChanged: (value) {
        setState(() {
          _portConfig = _portConfigHelper.updateScreenPort(_portConfig, value);
        });
      },
      onUseInternalProxyChanged: (value) {
        setState(() => _useInternalProxy = value);
      },
      onConnect: _connectToReceiver,
    );
  }
}
