import 'dart:async';
import 'package:flutter/material.dart';
import '../models/remote_control_config.dart';
import 'remote_control_session_page.dart';
import 'remote_control_page_connection_helper.dart';
import 'remote_control_page_port_config_helper.dart';
import 'remote_control_page_receiver_helper.dart';
import 'remote_control_disconnect_dialog.dart';
import 'remote_control_setup_sections.dart';
import '../services/remote_control_service.dart';
import '../services/remote_control_platform_gateway.dart';
import '../services/remote_control_protocol.dart' as protocol;
import '../services/app_lifecycle_manager.dart';
import '../services/app_log_service.dart';
import '../features/easytier/application/easytier_network_info_analyzer.dart';
import '../features/easytier/infrastructure/easytier_service.dart';
import '../services/app_toast.dart';
import '../features/proxy/infrastructure/proxy_service.dart';
import '../browser/browser_settings_service.dart';
import '../browser/browser_settings.dart';

part 'remote_control_page_peer_actions.dart';
part 'remote_control_page_receiver_actions.dart';

class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({super.key});

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
    required RemoteControlService service,
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
  final RemoteControlService _service = RemoteControlService();
  final RemoteControlPlatformGateway _platformGateway =
      RemoteControlPlatformGateway.instance;
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _controlPortController = TextEditingController();
  final TextEditingController _screenPortController = TextEditingController();
  final EasyTierService _easyTierService = EasyTierService();
  final ProxyService _proxyService = ProxyService();
  final BrowserSettingsService _settingsService = BrowserSettingsService();
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
  BrowserSettings? _settings;
  bool _isProxyRunning = false;
  bool _isReceiverRunning = false;
  bool _useReceiverNoTunMode = false;
  Timer? _peerRefreshTimer;
  bool _hadConnectedSession = false;
  bool _disconnectDialogVisible = false;

  late StreamSubscription<RemoteControlState> _stateSubscription;
  late StreamSubscription<protocol.ControlMessage> _messageSubscription;
  StreamSubscription<ProxyState>? _proxyStateSubscription;

  void _updateState(VoidCallback update) {
    setState(update);
  }

  void _showToast(String message) {
    unawaited(AppToast.show(message));
  }

  @override
  void initState() {
    super.initState();
    _stateSubscription = _service.stateStream.listen(_handleStateChange);
    _messageSubscription = _service.messageStream.listen(_handleMessage);
    _syncReceiverStateFromService();
    _applyPortConfigToInputs(_portConfig);
    _loadSettings();
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
      p2pNoTunMode: _easyTierService.isNoTunMode,
    );
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    if (mounted) {
      setState(() {
        _settings = settings;
        _isProxyRunning = _proxyService.isRunning;
      });
    }
    // 监听代理状态变化
    _proxyStateSubscription = _proxyService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isProxyRunning = state == ProxyState.started;
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

    final noTunControllerMode = _easyTierService.isNoTunMode;
    final candidatePorts = _buildCandidatePorts();
    final noTunProxyPort = _easyTierService.activeNoTunSocksPort;
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
          : await _connectionHelper.ensureInternalProxyReady(
              useInternalProxy: _useInternalProxy,
              settings: _settings,
              proxyService: _proxyService,
            );
    } on RemoteControlPageConnectionException catch (error) {
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
            builder: (context) =>
                RemoteControlSessionPage(service: _service, remoteHost: host),
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
      p2pNoTunMode: _easyTierService.isNoTunMode,
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
      isEasyTierRunning: _easyTierService.isRunning,
      isEasyTierNoTunMode: _easyTierService.isNoTunMode,
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
