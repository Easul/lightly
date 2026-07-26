import '../features/easytier/domain/easytier_config.dart';
import '../features/easytier/domain/easytier_network_profile.dart';
import 'easytier_profile_service.dart';

class EasyTierProfilesLoadResult {
  const EasyTierProfilesLoadResult({
    required this.profiles,
    required this.selectedProfile,
  });

  final List<EasyTierNetworkProfile> profiles;
  final EasyTierNetworkProfile selectedProfile;
}

class EasyTierProfileUpdateResult {
  const EasyTierProfileUpdateResult({
    required this.profiles,
    required this.selectedProfile,
  });

  final List<EasyTierNetworkProfile> profiles;
  final EasyTierNetworkProfile selectedProfile;
}

class EasyTierProfileCoordinator {
  const EasyTierProfileCoordinator({EasyTierProfileService? profileService})
    : _profileService = profileService;

  final EasyTierProfileService? _profileService;

  EasyTierProfileService get _service =>
      _profileService ?? EasyTierProfileService();

  Future<EasyTierProfilesLoadResult> loadProfiles() async {
    final profiles = await _service.loadProfiles();
    final selectedId =
        await _service.getSelectedProfileId() ?? profiles.first.id;
    final selectedProfile = profiles.firstWhere(
      (profile) => profile.id == selectedId,
      orElse: () => profiles.first,
    );
    return EasyTierProfilesLoadResult(
      profiles: profiles,
      selectedProfile: selectedProfile,
    );
  }

  Future<EasyTierProfileUpdateResult?> persistCurrentProfile({
    required String? selectedId,
    required List<EasyTierNetworkProfile> profiles,
    required EasyTierConfig currentConfig,
  }) async {
    if (selectedId == null || profiles.isEmpty) {
      return null;
    }

    late EasyTierNetworkProfile selectedProfile;
    final updatedProfiles = profiles.map((profile) {
      if (profile.id != selectedId) {
        return profile;
      }

      final profileName = currentConfig.networkName.trim().isEmpty
          ? profile.name
          : currentConfig.networkName.trim();
      final updated = profile.copyWith(
        name: profileName,
        config: currentConfig,
        updatedAt: DateTime.now(),
      );
      selectedProfile = updated;
      return updated;
    }).toList();

    await _service.saveProfiles(updatedProfiles);
    return EasyTierProfileUpdateResult(
      profiles: updatedProfiles,
      selectedProfile: selectedProfile,
    );
  }

  Future<EasyTierProfileUpdateResult?> selectProfile({
    required String? profileId,
    required List<EasyTierNetworkProfile> profiles,
  }) async {
    if (profileId == null) {
      return null;
    }
    EasyTierNetworkProfile? selectedProfile;
    for (final profile in profiles) {
      if (profile.id == profileId) {
        selectedProfile = profile;
        break;
      }
    }
    if (selectedProfile == null) {
      return null;
    }

    await _service.setSelectedProfileId(profileId);
    return EasyTierProfileUpdateResult(
      profiles: profiles,
      selectedProfile: selectedProfile,
    );
  }

  Future<EasyTierProfileUpdateResult> createProfile({
    required List<EasyTierNetworkProfile> profiles,
  }) async {
    final profile = _service.createProfile(
      name: '网络 ${profiles.length + 1}',
      config: EasyTierConfig(
        instanceName: 'ruoqing_vpn_${profiles.length + 1}',
        networkName: 'network_${profiles.length + 1}',
        networkSecret: '',
        ipv4: '',
        dhcp: false,
        peers: const <String>[],
        listeners: const <String>[],
        enableP2p: true,
        hostname: '',
      ),
    );
    final updatedProfiles = <EasyTierNetworkProfile>[...profiles, profile];
    await _service.saveProfiles(updatedProfiles);
    await _service.setSelectedProfileId(profile.id);
    return EasyTierProfileUpdateResult(
      profiles: updatedProfiles,
      selectedProfile: profile,
    );
  }

  Future<EasyTierProfileUpdateResult?> deleteCurrentProfile({
    required String? selectedProfileId,
    required List<EasyTierNetworkProfile> profiles,
  }) async {
    if (selectedProfileId == null || profiles.length <= 1) {
      return null;
    }
    final updatedProfiles = profiles
        .where((profile) => profile.id != selectedProfileId)
        .toList();
    final fallback = updatedProfiles.first;
    await _service.saveProfiles(updatedProfiles);
    await _service.setSelectedProfileId(fallback.id);
    return EasyTierProfileUpdateResult(
      profiles: updatedProfiles,
      selectedProfile: fallback,
    );
  }
}
