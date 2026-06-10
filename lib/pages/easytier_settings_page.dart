import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../browser/browser_settings.dart';
import '../browser/browser_settings_service.dart';
import '../browser/clipboard_http_server_service.dart';
import '../browser/local_http_file_server_service.dart';
import '../models/easytier_config.dart';
import '../models/easytier_network_profile.dart';
import '../services/easytier_network_info_analyzer.dart';
import '../services/easytier_profile_coordinator.dart';
import '../services/easytier_runtime_status_controller.dart';
import '../services/easytier_service_access_coordinator.dart';
import '../services/easytier_service.dart';
import 'easytier_settings_page_body.dart';

class EasyTierSettingsPage extends StatefulWidget {
  const EasyTierSettingsPage({super.key});

  @override
  State<EasyTierSettingsPage> createState() => _EasyTierSettingsPageState();
}

class _EasyTierSettingsPageState extends State<EasyTierSettingsPage> {
  final _easyTierService = EasyTierService();
  final _browserSettingsService = BrowserSettingsService();
  final _localHttpFileServerService = LocalHttpFileServerService();
  final _clipboardHttpServerService = ClipboardHttpServerService();
  final _profileCoordinator = EasyTierProfileCoordinator();
  final _serviceAccessCoordinator = const EasyTierServiceAccessCoordinator();
  late final EasyTierRuntimeStatusController _runtimeStatusController;
  final _formKey = GlobalKey<FormState>();

  final _instanceNameController = TextEditingController(text: 'ruoqing_vpn');
  final _networkNameController = TextEditingController();
  final _networkSecretController = TextEditingController();
  final _ipv4Controller = TextEditingController();
  final _hostnameController = TextEditingController();
  final _peerController = TextEditingController();
  final _portMappingPortController = TextEditingController();

  bool _dhcp = false;
  bool _enableP2p = true;
  bool _noTun = false;
  bool _portMappingsExpanded = false;
  List<String> _peers = [];
  List<String> _peerRemarks = [];
  List<EasyTierPortMapping> _portMappings = [];
  int? _activePeerIndex;
  bool _isRunning = false;
  bool _isLoading = false;
  String? _statusMessage;
  String? _errorMessage;
  Map<String, dynamic>? _networkInfo;
  BrowserSettings? _browserSettings;
  List<EasyTierNetworkProfile> _profiles = const <EasyTierNetworkProfile>[];
  String? _selectedProfileId;
  bool _isApplyingProfile = false;
  Timer? _refreshTimer;
  String? _lastAppliedEasyTierIp;

  @override
  void initState() {
    super.initState();
    _isRunning = _easyTierService.isRunning;
    _runtimeStatusController = EasyTierRuntimeStatusController(
      startVpn: _easyTierService.startVpn,
      startNoTun: _easyTierService.startNoTun,
      stopVpn: _easyTierService.stopVpn,
      getNetworkInfo: _easyTierService.getNetworkInfo,
      readLastError: () => _easyTierService.lastError,
    );
    _instanceNameController.addListener(_onFormChanged);
    _networkNameController.addListener(_onFormChanged);
    _networkSecretController.addListener(_onFormChanged);
    _ipv4Controller.addListener(_onFormChanged);
    _hostnameController.addListener(_onFormChanged);
    unawaited(_loadBrowserSettings());
    _loadStatus();
    unawaited(_loadProfiles());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _instanceNameController.removeListener(_onFormChanged);
    _networkNameController.removeListener(_onFormChanged);
    _networkSecretController.removeListener(_onFormChanged);
    _ipv4Controller.removeListener(_onFormChanged);
    _hostnameController.removeListener(_onFormChanged);
    _instanceNameController.dispose();
    _networkNameController.dispose();
    _networkSecretController.dispose();
    _ipv4Controller.dispose();
    _hostnameController.dispose();
    _peerController.dispose();
    _portMappingPortController.dispose();
    super.dispose();
  }

  EasyTierConfig _buildCurrentConfig() {
    return EasyTierConfig(
      instanceName: _instanceNameController.text.trim(),
      networkName: _networkNameController.text.trim(),
      networkSecret: _networkSecretController.text.trim(),
      ipv4: _dhcp ? null : _ipv4Controller.text.trim(),
      dhcp: _dhcp,
      peers: List<String>.from(_peers),
      peerRemarks: List<String>.from(_normalizedPeerRemarks()),
      activePeerIndex: _effectiveActivePeerIndex(),
      enableP2p: _enableP2p,
      noTun: _noTun,
      portMappings: List<EasyTierPortMapping>.from(_portMappings),
      hostname: _hostnameController.text.trim().isEmpty
          ? null
          : _hostnameController.text.trim(),
    );
  }

  Future<void> _loadProfiles() async {
    final result = await _profileCoordinator.loadProfiles();
    if (!mounted) return;
    setState(() {
      _profiles = result.profiles;
      _selectedProfileId = result.selectedProfile.id;
    });
    _applyProfile(result.selectedProfile);
  }

  Future<void> _loadBrowserSettings() async {
    final settings = await _browserSettingsService.loadSettings();
    if (!mounted) return;
    setState(() {
      _browserSettings = settings;
    });
  }

  void _applyProfile(EasyTierNetworkProfile profile) {
    _isApplyingProfile = true;
    _instanceNameController.text = profile.config.instanceName;
    _networkNameController.text = profile.config.networkName;
    _networkSecretController.text = profile.config.networkSecret ?? '';
    _dhcp = profile.config.dhcp;
    _ipv4Controller.text = profile.config.ipv4 ?? '';
    _hostnameController.text = profile.config.hostname ?? '';
    _enableP2p = profile.config.enableP2p;
    _noTun = profile.config.noTun;
    _peers = List<String>.from(profile.config.peers);
    _peerRemarks = _normalizePeerRemarks(profile.config.peerRemarks, _peers);
    _portMappings = List<EasyTierPortMapping>.from(profile.config.portMappings);
    _activePeerIndex = _normalizeActivePeerIndex(
      profile.config.activePeerIndex,
      _peers,
    );
    _selectedProfileId = profile.id;
    _isApplyingProfile = false;
    if (mounted) {
      setState(() {});
    }
  }

  void _onFormChanged() {
    if (_isApplyingProfile) return;
    unawaited(_persistCurrentProfile());
  }

  Future<void> _persistCurrentProfile() async {
    final result = await _profileCoordinator.persistCurrentProfile(
      selectedId: _selectedProfileId,
      profiles: _profiles,
      currentConfig: _buildCurrentConfig(),
    );
    if (result == null || !mounted) return;
    if (!mounted) return;
    setState(() {
      _profiles = result.profiles;
    });
  }

  Future<void> _selectProfile(String? profileId) async {
    final result = await _profileCoordinator.selectProfile(
      profileId: profileId,
      profiles: _profiles,
    );
    if (result == null) return;
    _applyProfile(result.selectedProfile);
  }

  Future<void> _createNewProfile() async {
    final result = await _profileCoordinator.createProfile(profiles: _profiles);
    if (!mounted) return;
    setState(() {
      _profiles = result.profiles;
    });
    _applyProfile(result.selectedProfile);
  }

  Future<void> _deleteCurrentProfile() async {
    final result = await _profileCoordinator.deleteCurrentProfile(
      selectedProfileId: _selectedProfileId,
      profiles: _profiles,
    );
    if (result == null) return;
    if (!mounted) return;
    setState(() {
      _profiles = result.profiles;
    });
    _applyProfile(result.selectedProfile);
  }

  Future<void> _loadStatus() async {
    if (_isRunning) {
      final result = await _runtimeStatusController.loadStatus(
        instanceName: _instanceNameController.text,
        previousIp: _lastAppliedEasyTierIp,
      );
      if (!mounted) {
        return;
      }
      if (result.errorMessage != null) {
        setState(() {
          _errorMessage = result.errorMessage;
        });
        return;
      }
      setState(() {
        _networkInfo = result.networkInfo;
        _lastAppliedEasyTierIp = result.nextIp;
      });
      if (result.shouldRestartServices) {
        unawaited(_restartServicesForEasyTierIp());
      }
    }
  }

  Map<String, dynamic>? _currentInstanceNetworkInfo() {
    return EasyTierNetworkInfoAnalyzer.currentInstanceNetworkInfo(
      _networkInfo,
      _instanceNameController.text,
    );
  }

  void _updateRefreshTimer() {
    _refreshTimer?.cancel();
    if (!_isRunning) {
      _refreshTimer = null;
      return;
    }

    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_loadStatus());
    });
  }

  List<Map<String, String>> _buildPeerSummaries() {
    return EasyTierNetworkInfoAnalyzer.buildPeerSummaries(
      _networkInfo,
      _instanceNameController.text,
    );
  }

  List<String> _buildDiagnostics() {
    final diagnostics = EasyTierNetworkInfoAnalyzer.buildDiagnostics(
      _networkInfo,
      _instanceNameController.text,
    );
    final socksPort = _easyTierService.activeNoTunSocksPort;
    if (socksPort == null) {
      return diagnostics;
    }
    return <String>[
      '非 VPN 模式 SOCKS5 端口：$socksPort（应用连接 127.0.0.1:$socksPort）',
      ...diagnostics,
    ];
  }

  String? _currentEasyTierIpv4() {
    final networkInfo = _currentInstanceNetworkInfo();
    if (networkInfo == null) {
      return null;
    }
    final myNodeInfo = networkInfo['my_node_info'];
    if (myNodeInfo is! Map) {
      return null;
    }
    return EasyTierNetworkInfoAnalyzer.decodeIpv4(
      myNodeInfo['virtual_ipv4'] is Map
          ? Map<String, dynamic>.from(myNodeInfo['virtual_ipv4'] as Map)
          : null,
    );
  }

  String _formattedNetworkInfoText() {
    return EasyTierNetworkInfoAnalyzer.formattedNetworkInfoText(
      rawNetworkInfo: _easyTierService.lastRawNetworkInfo,
      networkInfo: _networkInfo,
      instanceName: _instanceNameController.text,
    );
  }

  Future<void> _enableLocalHttpVpnExposure() async {
    final result = _serviceAccessCoordinator.enableLocalHttpVpnExposure(
      _browserSettings,
    );
    if (result == null) {
      return;
    }
    await _browserSettingsService.saveSettings(result.settings);
    await _localHttpFileServerService.applySettings(result.settings);
    if (!mounted) return;
    setState(() {
      _browserSettings = result.settings;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _startClipboardServiceIfNeeded() async {
    final result = _serviceAccessCoordinator.startClipboardServiceIfNeeded(
      isRunning: _clipboardHttpServerService.isRunning,
    );
    if (!result.didChange) {
      return;
    }
    await _clipboardHttpServerService.start(preferredPort: 12345);
    if (!mounted) return;
    setState(() {});
    if (result.message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message!)));
    }
  }

  Future<void> _restartServicesForEasyTierIp() async {
    final plan = _serviceAccessCoordinator.buildRestartPlan(
      browserSettings: _browserSettings,
      clipboardRunning: _clipboardHttpServerService.isRunning,
      configuredClipboardPort: _clipboardHttpServerService.configuredPort,
      boundClipboardPort: _clipboardHttpServerService.boundPort,
    );
    if (plan.localHttpSettings != null) {
      await _localHttpFileServerService.applySettings(plan.localHttpSettings!);
    }

    if (plan.restartClipboard) {
      await _clipboardHttpServerService.start(
        preferredPort: plan.preferredClipboardPort,
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _copyNetworkInfo() async {
    final formatted = _formattedNetworkInfoText();
    if (formatted.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: formatted));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('网络信息已复制')));
  }

  void _addPeer() {
    final peer = _peerController.text.trim();
    if (peer.isNotEmpty) {
      setState(() {
        _peers.add(peer);
        _peerRemarks.add('');
        _activePeerIndex ??= 0;
        _peerController.clear();
      });
      unawaited(_persistCurrentProfile());
    }
  }

  void _removePeer(int index) {
    setState(() {
      final activeIndex = _effectiveActivePeerIndex();
      _peers.removeAt(index);
      if (index < _peerRemarks.length) {
        _peerRemarks.removeAt(index);
      }
      if (_peers.isEmpty) {
        _activePeerIndex = null;
      } else if (activeIndex == index) {
        _activePeerIndex = index.clamp(0, _peers.length - 1);
      } else if (activeIndex != null && activeIndex > index) {
        _activePeerIndex = activeIndex - 1;
      }
    });
    unawaited(_persistCurrentProfile());
  }

  void _selectPeer(int index) {
    if (index < 0 || index >= _peers.length) return;
    setState(() {
      _activePeerIndex = index;
    });
    unawaited(_persistCurrentProfile());
  }

  void _updatePeerRemark(int index, String remark) {
    if (index < 0 || index >= _peers.length) return;
    setState(() {
      _peerRemarks = _normalizedPeerRemarks();
      _peerRemarks[index] = remark;
    });
    unawaited(_persistCurrentProfile());
  }

  void _addPortMapping() {
    final port = int.tryParse(_portMappingPortController.text.trim());
    if (port == null || port <= 0 || port >= 65536) {
      return;
    }
    setState(() {
      if (!_portMappings.any((mapping) => mapping.port == port)) {
        _portMappings.add(EasyTierPortMapping(port: port));
      }
      _portMappingPortController.clear();
      _portMappingsExpanded = true;
    });
    unawaited(_persistCurrentProfile());
  }

  void _removePortMapping(int index) {
    if (index < 0 || index >= _portMappings.length) return;
    setState(() {
      _portMappings.removeAt(index);
    });
    unawaited(_persistCurrentProfile());
  }

  void _updatePortMappingRemark(int index, String remark) {
    if (index < 0 || index >= _portMappings.length) return;
    setState(() {
      _portMappings[index] = _portMappings[index].copyWith(remark: remark);
    });
    unawaited(_persistCurrentProfile());
  }

  int? _effectiveActivePeerIndex() {
    return _normalizeActivePeerIndex(_activePeerIndex, _peers);
  }

  List<String> _normalizedPeerRemarks() {
    return _normalizePeerRemarks(_peerRemarks, _peers);
  }

  List<String> _normalizePeerRemarks(List<String> remarks, List<String> peers) {
    return List<String>.generate(
      peers.length,
      (index) => index < remarks.length ? remarks[index] : '',
    );
  }

  int? _normalizeActivePeerIndex(int? index, List<String> peers) {
    if (peers.isEmpty) return null;
    if (index == null || index < 0 || index >= peers.length) return 0;
    return index;
  }

  Future<void> _startVpn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = _noTun
          ? '正在启动 EasyTier 非 VPN 模式...'
          : '正在启动 EasyTier VPN，必要时会请求系统权限...';
    });

    final result = await _runtimeStatusController.startVpn(
      _buildCurrentConfig(),
      useNoTunMode: _noTun,
    );
    setState(() {
      _isLoading = false;
      _isRunning = result.isRunning;
      final socksPort = _easyTierService.activeNoTunSocksPort;
      _statusMessage = socksPort == null
          ? result.statusMessage
          : '${result.statusMessage}，SOCKS5 端口：$socksPort';
      _errorMessage = result.errorMessage;
    });
    _updateRefreshTimer();
    if (result.shouldLoadStatus) {
      unawaited(_loadStatus());
    }
  }

  Future<void> _stopVpn() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在停止 VPN...';
    });

    final result = await _runtimeStatusController.stopVpn();
    setState(() {
      _isLoading = false;
      _isRunning = result.isRunning;
      _statusMessage = result.statusMessage;
      _errorMessage = result.errorMessage;
      if (result.clearNetworkInfo) {
        _networkInfo = null;
      }
    });
    _updateRefreshTimer();
  }

  Future<void> _refreshStatus() async {
    await _loadStatus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final peerSummaries = _buildPeerSummaries();
    final diagnostics = _buildDiagnostics();
    final easyTierIpv4 = _currentEasyTierIpv4();
    final easyTierIp = easyTierIpv4?.split('/').first;
    final displayNetworkInfo = _formattedNetworkInfoText();
    final browserSettings = _browserSettings;
    final localHttpReachable =
        browserSettings != null &&
        browserSettings.localHttpServerEnabled &&
        browserSettings.localHttpBindAllInterfaces &&
        _localHttpFileServerService.boundPort != null;
    final clipboardReachable =
        _clipboardHttpServerService.isRunning &&
        _clipboardHttpServerService.boundPort != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P VPN 设置'),
        actions: [
          if (_isRunning)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshStatus,
            ),
        ],
      ),
      body: EasyTierSettingsBody(
        formKey: _formKey,
        isRunning: _isRunning,
        isLoading: _isLoading,
        statusMessage: _statusMessage,
        errorMessage: _errorMessage,
        profiles: _profiles,
        selectedProfileId: _selectedProfileId,
        peerSummaries: peerSummaries,
        diagnostics: diagnostics,
        displayNetworkInfo: displayNetworkInfo,
        easyTierIp: easyTierIp,
        localHttpReachable: localHttpReachable,
        localHttpSubtitle: easyTierIp != null && localHttpReachable
            ? 'http://$easyTierIp:${_localHttpFileServerService.boundPort}'
            : '当前未处于 VPN 可访问模式',
        clipboardReachable: clipboardReachable,
        clipboardSubtitle: easyTierIp != null && clipboardReachable
            ? 'http://$easyTierIp:${_clipboardHttpServerService.boundPort}'
            : '服务未运行',
        instanceNameController: _instanceNameController,
        networkNameController: _networkNameController,
        networkSecretController: _networkSecretController,
        dhcp: _dhcp,
        ipv4Controller: _ipv4Controller,
        hostnameController: _hostnameController,
        enableP2p: _enableP2p,
        noTun: _noTun,
        portMappingPortController: _portMappingPortController,
        portMappings: _portMappings,
        portMappingsExpanded: _portMappingsExpanded,
        peerController: _peerController,
        peers: _peers,
        peerRemarks: _normalizedPeerRemarks(),
        activePeerIndex: _effectiveActivePeerIndex(),
        onSelectProfile: (profileId) => unawaited(_selectProfile(profileId)),
        onCreateProfile: () => unawaited(_createNewProfile()),
        onDeleteProfile: () => unawaited(_deleteCurrentProfile()),
        onCopyNetworkInfo: () => unawaited(_copyNetworkInfo()),
        onEnableLocalHttp: () => unawaited(_enableLocalHttpVpnExposure()),
        onStartClipboard: () => unawaited(_startClipboardServiceIfNeeded()),
        onStartVpn: () => unawaited(_startVpn()),
        onStopVpn: () => unawaited(_stopVpn()),
        onDhcpChanged: (value) {
          setState(() {
            _dhcp = value;
          });
          unawaited(_persistCurrentProfile());
        },
        onEnableP2pChanged: (value) {
          setState(() {
            _enableP2p = value;
          });
          unawaited(_persistCurrentProfile());
        },
        onNoTunChanged: (value) {
          setState(() {
            _noTun = value;
          });
          unawaited(_persistCurrentProfile());
        },
        onPortMappingsExpandedChanged: (value) {
          setState(() {
            _portMappingsExpanded = value;
          });
        },
        onAddPortMapping: _addPortMapping,
        onRemovePortMapping: _removePortMapping,
        onPortMappingRemarkChanged: _updatePortMappingRemark,
        onAddPeer: _addPeer,
        onRemovePeer: _removePeer,
        onSelectPeer: _selectPeer,
        onPeerRemarkChanged: _updatePeerRemark,
      ),
    );
  }
}
