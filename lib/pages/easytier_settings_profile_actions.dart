part of 'easytier_settings_page.dart';

extension _EasyTierSettingsProfileActions on _EasyTierSettingsPageState {
  Future<void> _loadProfiles() async {
    final result = await _profileCoordinator.loadProfiles();
    if (!mounted) return;
    _updateState(() {
      _profiles = result.profiles;
      _selectedProfileId = result.selectedProfile.id;
    });
    _applyProfile(result.selectedProfile);
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
      _updateState(() {});
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
    _updateState(() {
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
    _updateState(() {
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
    _updateState(() {
      _profiles = result.profiles;
    });
    _applyProfile(result.selectedProfile);
  }
}
