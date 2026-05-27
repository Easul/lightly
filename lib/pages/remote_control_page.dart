import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/remote_control_config.dart';
import 'remote_control_session_page.dart';
import 'remote_control_page_connection_helper.dart';
import 'remote_control_page_port_config_helper.dart';
import 'remote_control_page_receiver_helper.dart';
import 'remote_control_setup_sections.dart';
import '../services/remote_control_service.dart';
import '../services/remote_control_protocol.dart' as protocol;
import '../services/app_lifecycle_manager.dart';
import '../services/easytier_service.dart';
import '../services/easytier_network_info_analyzer.dart';
import '../services/app_toast.dart';
import '../browser/proxy_service.dart';
import '../browser/browser_settings_service.dart';
import '../browser/browser_settings.dart';

class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({super.key});

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage> {
  static const MethodChannel _channel = MethodChannel('remote_control');
  final RemoteControlService _service = RemoteControlService();
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
  bool _portsManuallyEdited = false;

  late StreamSubscription<RemoteControlState> _stateSubscription;
  late StreamSubscription<protocol.ControlMessage> _messageSubscription;
  StreamSubscription<ProxyState>? _proxyStateSubscription;

  void _showToast(String message) {
    unawaited(AppToast.show(message));
  }

  @override
  void initState() {
    super.initState();
    _stateSubscription = _service.stateStream.listen(_handleStateChange);
    _messageSubscription = _service.messageStream.listen(_handleMessage);
    _portConfig = _service.config?.ports;
    _applyPortConfigToInputs(_portConfig);
    _loadSettings();
    _loadPeers();
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
    _proxyStateSubscription?.cancel();
    _stateSubscription.cancel();
    _messageSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadPeers() async {
    if (!_easyTierService.isRunning) return;

    setState(() => _isLoadingPeers = true);

    try {
      final networkInfo = await _easyTierService.getNetworkInfo();
      if (networkInfo != null) {
        final peers = EasyTierNetworkInfoAnalyzer.buildPeerSummaries(
          networkInfo,
          'default',
        );
        if (!mounted) return;
        setState(() {
          _peers = peers;
          _isLoadingPeers = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _isLoadingPeers = false);
      }
    } catch (e) {
      developer.log('Failed to load peers: $e', name: 'RemoteControl');
      if (!mounted) return;
      setState(() => _isLoadingPeers = false);
    }
  }

  void _handleStateChange(RemoteControlState state) {
    if (!mounted) return;
    setState(() {
      _isConnecting = state == RemoteControlState.connecting;
      _isReceiverAudioEnabled = _service.isLocalAudioEnabled;
      if (state == RemoteControlState.connected) {
        _errorMessage = null;
      } else if (state == RemoteControlState.error) {
        _errorMessage = '连接失败';
      } else if (state == RemoteControlState.disconnected) {
        _errorMessage = null;
      }
    });
  }

  void _handleMessage(protocol.ControlMessage message) {
    if (message is protocol.StatusMessage &&
        message.action == 'receiver_info') {
      return;
    }
  }

  Future<void> _startReceiver() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final ports = await _receiverHelper.startReceiverFlow(
        channel: _channel,
        service: _service,
        ensureVpnForRemoteControl:
            AppLifecycleManager().ensureVpnForRemoteControl,
      );

      if (!mounted) return;
      setState(() {
        _portConfig = ports;
        _isConnecting = false;
      });
      _applyPortConfigToInputs(ports);

      if (mounted) {
        _showToast('被控端已启动，端口: ${ports.controlPort}/${ports.screenPort}');
      }
    } on RemoteControlPageReceiverStartException catch (error) {
      if (!mounted) return;
      _showToast(error.message);
      setState(() => _isConnecting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _errorMessage = '启动失败: $e';
      });
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
    });

    int? proxyPort;
    try {
      proxyPort = await _connectionHelper.ensureInternalProxyReady(
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

    if (!_portsManuallyEdited) {
      final discoveredPorts = await _connectionHelper.discoverReceiverPorts(
        service: _service,
        host: host,
        useInternalProxy: _useInternalProxy,
        proxyPort: proxyPort,
      );
      if (discoveredPorts != null && mounted) {
        setState(() {
          _portConfig = discoveredPorts;
        });
        _applyPortConfigToInputs(discoveredPorts);
      }
    }

    Object? lastError;
    for (final ports in _buildCandidatePorts()) {
      try {
        await _service.connectToReceiver(
          host,
          ports,
          useProxy: _useInternalProxy,
          proxyPort: proxyPort,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _isConnecting = false;
          _portConfig = _service.config?.ports ?? ports;
          _portsManuallyEdited = false;
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

  Future<void> _selectPeer(Map<String, String> peer) async {
    final host = _normalizeHost(peer['ip'] ?? '');
    if (host.isEmpty) {
      return;
    }

    setState(() {
      _hostController.text = host;
      _portConfig = null;
      _portsManuallyEdited = false;
      _errorMessage = null;
    });
    _applyPortConfigToInputs(null);

    final discoveredPorts = await _connectionHelper.discoverReceiverPorts(
      service: _service,
      host: host,
      useInternalProxy: _useInternalProxy,
      proxyPort: _useInternalProxy ? _proxyService.localProxyPort : null,
    );
    if (!mounted || discoveredPorts == null) {
      return;
    }

    setState(() {
      _portConfig = discoveredPorts;
    });
    _applyPortConfigToInputs(discoveredPorts);
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
        _portsManuallyEdited = false;
        _applyPortConfigToInputs(null);
        _errorMessage = null;
      }),
    );
  }

  Widget _buildReceiverSection() {
    return RemoteControlReceiverSection(
      portConfig: _portConfig,
      isReceiverAudioEnabled: _isReceiverAudioEnabled,
      state: _service.state,
      isConnecting: _isConnecting,
      onToggleReceiverMic: _toggleReceiverMic,
      onStartReceiver: _startReceiver,
    );
  }

  Widget _buildControllerSection() {
    return RemoteControlControllerSection(
      peers: _peers,
      isEasyTierRunning: _easyTierService.isRunning,
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
          _portsManuallyEdited = true;
          _portConfig = _portConfigHelper.updateControlPort(_portConfig, value);
        });
      },
      onScreenPortChanged: (value) {
        setState(() {
          _portsManuallyEdited = true;
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
