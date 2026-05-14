import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/remote_control_config.dart';
import 'remote_control_session_page.dart';
import 'remote_control_setup_sections.dart';
import '../services/remote_control_service.dart';
import '../services/remote_control_protocol.dart' as protocol;
import '../services/easytier_service.dart';
import '../services/easytier_network_info_analyzer.dart';

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
  final TextEditingController _audioPortController = TextEditingController();
  final EasyTierService _easyTierService = EasyTierService();

  RemoteControlMode _selectedMode = RemoteControlMode.controller;
  RemoteControlPortConfig? _portConfig;
  bool _isConnecting = false;
  bool _isReceiverAudioEnabled = false;
  String? _errorMessage;
  List<Map<String, String>> _peers = [];
  bool _isLoadingPeers = false;

  late StreamSubscription<RemoteControlState> _stateSubscription;
  late StreamSubscription<protocol.ControlMessage> _messageSubscription;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _service.stateStream.listen(_handleStateChange);
    _messageSubscription = _service.messageStream.listen(_handleMessage);
    _portConfig = _service.config?.ports;
    _applyPortConfigToInputs(_portConfig);
    _loadPeers();
  }

  @override
  void dispose() {
    if (_service.mode == RemoteControlMode.receiver || _service.isConnected) {
      unawaited(_service.disconnect());
    }
    _hostController.dispose();
    _controlPortController.dispose();
    _screenPortController.dispose();
    _audioPortController.dispose();
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
      _isReceiverAudioEnabled = _service.audioCaptureService.isCapturing;
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
    developer.log('Received message: ${message.type}', name: 'RemoteControl');
  }

  Future<void> _startReceiver() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final config = await RemoteControlConfig.defaultConfig();

      final hasPermission =
          await _channel.invokeMethod<bool>('checkAccessibilityPermission') ??
          false;
      if (!hasPermission) {
        await _channel.invokeMethod('openAccessibilitySettings');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('请在无障碍设置中开启本应用的权限，然后返回重试'),
              duration: Duration(seconds: 5),
            ),
          );
        }
        setState(() => _isConnecting = false);
        return;
      }

      final ports = await _service.startReceiver(config: config);

      await _service.startScreenCapture(
        fps: config.screenFps,
        bitrate: config.screenBitrate,
      );

      if (!mounted) return;
      setState(() {
        _portConfig = ports;
        _isConnecting = false;
      });
      _applyPortConfigToInputs(ports);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '被控端已启动，端口: ${ports.controlPort}/${ports.screenPort}/${ports.audioPort}',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先等待主控端连接后再切换麦克风')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法启动麦克风，请检查权限')));
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

    if (_portConfig == null) {
      final discoveredPorts = await _service.discoverReceiverPorts(host);
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
        await _service.connectToReceiver(host, ports);
        if (!mounted) {
          return;
        }
        setState(() {
          _isConnecting = false;
          _portConfig = _service.config?.ports ?? ports;
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
      _errorMessage = '连接失败: ${lastError ?? '请检查地址、端口和被控端是否已启动'}';
    });
  }

  List<RemoteControlPortConfig> _buildCandidatePorts() {
    if (_portConfig != null) {
      return <RemoteControlPortConfig>[_portConfig!];
    }

    return <RemoteControlPortConfig>[
      for (final basePort in RemoteControlPortConfig.shuffledBasePorts())
        RemoteControlPortConfig.fromBasePort(basePort),
    ];
  }

  String _normalizeHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final slashIndex = trimmed.indexOf('/');
    if (slashIndex <= 0) {
      return trimmed;
    }
    return trimmed.substring(0, slashIndex);
  }

  Future<void> _selectPeer(Map<String, String> peer) async {
    final host = _normalizeHost(peer['ip'] ?? '');
    if (host.isEmpty) {
      return;
    }

    setState(() {
      _hostController.text = host;
      _portConfig = null;
      _errorMessage = null;
    });
    _applyPortConfigToInputs(null);

    final discoveredPorts = await _service.discoverReceiverPorts(host);
    if (!mounted || discoveredPorts == null) {
      return;
    }

    setState(() {
      _portConfig = discoveredPorts;
    });
    _applyPortConfigToInputs(discoveredPorts);
  }

  void _applyPortConfigToInputs(RemoteControlPortConfig? ports) {
    final resolved =
        ports ??
        const RemoteControlPortConfig(
          controlPort: 18080,
          screenPort: 18081,
          audioPort: 18082,
        );
    _controlPortController.text = '${resolved.controlPort}';
    _screenPortController.text = '${resolved.screenPort}';
    _audioPortController.text = '${resolved.audioPort}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('远程控制')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
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
      audioPortController: _audioPortController,
      portConfig: _portConfig,
      isConnecting: _isConnecting,
      onReloadPeers: _loadPeers,
      onSelectPeer: _selectPeer,
      onControlPortChanged: (value) {
        setState(() {
          _portConfig = RemoteControlPortConfig(
            controlPort: value,
            screenPort: _portConfig?.screenPort ?? 18081,
            audioPort: _portConfig?.audioPort ?? 18082,
          );
        });
      },
      onScreenPortChanged: (value) {
        setState(() {
          _portConfig = RemoteControlPortConfig(
            controlPort: _portConfig?.controlPort ?? 18080,
            screenPort: value,
            audioPort: _portConfig?.audioPort ?? 18082,
          );
        });
      },
      onAudioPortChanged: (value) {
        setState(() {
          _portConfig = RemoteControlPortConfig(
            controlPort: _portConfig?.controlPort ?? 18080,
            screenPort: _portConfig?.screenPort ?? 18081,
            audioPort: value,
          );
        });
      },
      onConnect: _connectToReceiver,
    );
  }
}
