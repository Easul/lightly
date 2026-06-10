part of 'easytier_settings_page.dart';

extension _EasyTierSettingsRuntimeActions on _EasyTierSettingsPageState {
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
        _updateState(() {
          _errorMessage = result.errorMessage;
        });
        return;
      }
      _updateState(() {
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

  Future<void> _startVpn() async {
    if (!_formKey.currentState!.validate()) return;

    _updateState(() {
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
    _updateState(() {
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
    _updateState(() {
      _isLoading = true;
      _statusMessage = '正在停止 VPN...';
    });

    final result = await _runtimeStatusController.stopVpn();
    _updateState(() {
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
    _updateState(() {});
  }
}
