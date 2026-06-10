part of 'easytier_settings_page.dart';

extension _EasyTierSettingsPeerFormActions on _EasyTierSettingsPageState {
  void _addPeer() {
    final peer = _peerController.text.trim();
    if (peer.isNotEmpty) {
      _updateState(() {
        _peers.add(peer);
        _peerRemarks.add('');
        _activePeerIndex ??= 0;
        _peerController.clear();
      });
      unawaited(_persistCurrentProfile());
    }
  }

  void _removePeer(int index) {
    _updateState(() {
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
    _updateState(() {
      _activePeerIndex = index;
    });
    unawaited(_persistCurrentProfile());
  }

  void _updatePeerRemark(int index, String remark) {
    if (index < 0 || index >= _peers.length) return;
    _updateState(() {
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
    _updateState(() {
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
    _updateState(() {
      _portMappings.removeAt(index);
    });
    unawaited(_persistCurrentProfile());
  }

  void _updatePortMappingRemark(int index, String remark) {
    if (index < 0 || index >= _portMappings.length) return;
    _updateState(() {
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
}
