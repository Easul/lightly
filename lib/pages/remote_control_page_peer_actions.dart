part of 'remote_control_page.dart';

extension _RemoteControlPagePeerActions on _RemoteControlPageState {
  Future<void> _loadPeers({bool showLoading = true}) async {
    if (_easyTierService.isNoTunMode && !_useReceiverNoTunMode && mounted) {
      _updateState(_syncReceiverNoTunModeFromP2p);
    }

    if (!_easyTierService.isRunning) {
      if (mounted && _peers.isNotEmpty) {
        _updateState(() => _peers = const <Map<String, String>>[]);
      }
      return;
    }

    if (showLoading && mounted) {
      _updateState(() => _isLoadingPeers = true);
    }

    try {
      final networkInfo = await _easyTierService.getNetworkInfo();
      if (networkInfo != null) {
        final peers = EasyTierNetworkInfoAnalyzer.buildPeerSummaries(
          networkInfo,
          _easyTierService.currentInstanceName ?? 'ruoqing_vpn',
        ).where((peer) => peer['remoteReachable'] == 'true').toList();
        if (!mounted) return;
        _updateState(() {
          _peers = peers;
          if (showLoading) {
            _isLoadingPeers = false;
          }
        });
      } else {
        if (!mounted) return;
        if (showLoading) {
          _updateState(() => _isLoadingPeers = false);
        }
      }
    } catch (e) {
      developer.log('Failed to load peers: $e', name: 'RemoteControl');
      if (!mounted) return;
      if (showLoading) {
        _updateState(() => _isLoadingPeers = false);
      }
    }
  }

  Future<void> _selectPeer(Map<String, String> peer) async {
    final host = _normalizeHost(peer['ip'] ?? '');
    if (host.isEmpty) {
      return;
    }

    _updateState(() {
      _hostController.text = host;
      _portConfig = null;
      _errorMessage = null;
    });
    _applyPortConfigToInputs(null);

    final noTunControllerMode = _easyTierService.isNoTunMode;
    final noTunProxyPort = _easyTierService.activeNoTunSocksPort;
    if (noTunControllerMode && noTunProxyPort == null) {
      return;
    }

    final discoveredPorts = await _connectionHelper.discoverReceiverPorts(
      service: _service,
      host: host,
      useInternalProxy: noTunControllerMode || _useInternalProxy,
      proxyPort: noTunControllerMode
          ? noTunProxyPort
          : _proxyService.localProxyPort,
    );
    if (!mounted || discoveredPorts == null) {
      return;
    }

    _updateState(() {
      _portConfig = discoveredPorts;
    });
    _applyPortConfigToInputs(discoveredPorts);
  }
}
