import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../browser/browser_settings.dart';
import '../browser/browser_settings_service.dart';
import '../features/local_sharing/clipboard/clipboard_http_server_service.dart';
import '../features/local_sharing/local_http/local_http_file_server_service.dart';
import '../browser/services/browser_runtime_coordinator.dart';
import '../models/easytier_config.dart';
import '../models/easytier_network_profile.dart';
import '../services/easytier_network_info_analyzer.dart';
import '../services/easytier_profile_coordinator.dart';
import '../services/easytier_runtime_status_controller.dart';
import '../services/easytier_service_access_coordinator.dart';
import '../services/easytier_service.dart';
import '../app/app_runtime_coordinator.dart';
import 'easytier_settings_page_body.dart';

part 'easytier_settings_profile_actions.dart';
part 'easytier_settings_runtime_actions.dart';
part 'easytier_settings_peer_form_actions.dart';

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

  void _updateState(VoidCallback update) {
    setState(update);
  }

  @override
  void initState() {
    super.initState();
    _isRunning = _easyTierService.isRunning;
    _runtimeStatusController = EasyTierRuntimeStatusController(
      startVpn: (config) => AppRuntimeCoordinator.instance.startEasyTier(
        config,
        useNoTunMode: false,
      ),
      startNoTun: (config) => AppRuntimeCoordinator.instance.startEasyTier(
        config,
        useNoTunMode: true,
      ),
      stopVpn: AppRuntimeCoordinator.instance.stopEasyTier,
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

  Future<void> _loadBrowserSettings() async {
    final settings = await _browserSettingsService.loadSettings();
    if (!mounted) return;
    setState(() {
      _browserSettings = settings;
    });
  }

  Future<void> _enableLocalHttpVpnExposure() async {
    final result = _serviceAccessCoordinator.enableLocalHttpVpnExposure(
      _browserSettings,
    );
    if (result == null) {
      return;
    }
    await _browserSettingsService.saveSettings(result.settings);
    await BrowserRuntimeCoordinator.instance.applyLocalHttpSettings(
      result.settings,
    );
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
    await BrowserRuntimeCoordinator.instance.startClipboard(
      preferredPort: 12345,
    );
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
      await BrowserRuntimeCoordinator.instance.applyLocalHttpSettings(
        plan.localHttpSettings!,
      );
    }

    if (plan.restartClipboard) {
      await BrowserRuntimeCoordinator.instance.startClipboard(
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
