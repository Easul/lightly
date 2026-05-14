import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/easytier_config.dart';
import '../models/easytier_network_profile.dart';

class EasyTierProfileService {
  static const String _profilesKey = 'easytier_profiles';
  static const String _selectedProfileIdKey = 'easytier_selected_profile_id';

  Future<List<EasyTierNetworkProfile>> loadProfiles() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_profilesKey);
    if (raw == null || raw.isEmpty) {
      final defaultProfile = _createDefaultProfile();
      await saveProfiles(<EasyTierNetworkProfile>[defaultProfile]);
      await setSelectedProfileId(defaultProfile.id);
      return <EasyTierNetworkProfile>[defaultProfile];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    final profiles = decoded
        .map(
          (item) => EasyTierNetworkProfile.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();

    if (profiles.isEmpty) {
      final defaultProfile = _createDefaultProfile();
      await saveProfiles(<EasyTierNetworkProfile>[defaultProfile]);
      await setSelectedProfileId(defaultProfile.id);
      return <EasyTierNetworkProfile>[defaultProfile];
    }

    return profiles;
  }

  Future<void> saveProfiles(List<EasyTierNetworkProfile> profiles) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      profiles.map((profile) => profile.toJson()).toList(),
    );
    await preferences.setString(_profilesKey, encoded);

    final selectedId = preferences.getString(_selectedProfileIdKey);
    if (selectedId == null ||
        profiles.any((profile) => profile.id == selectedId)) {
      return;
    }

    await preferences.setString(_selectedProfileIdKey, profiles.first.id);
  }

  Future<String?> getSelectedProfileId() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_selectedProfileIdKey);
  }

  Future<void> setSelectedProfileId(String id) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_selectedProfileIdKey, id);
  }

  EasyTierNetworkProfile createProfile({String? name, EasyTierConfig? config}) {
    final now = DateTime.now();
    final effectiveConfig = config ?? _defaultConfig();
    return EasyTierNetworkProfile(
      id: now.microsecondsSinceEpoch.toString(),
      name: name ?? effectiveConfig.networkName,
      config: effectiveConfig,
      createdAt: now,
      updatedAt: now,
    );
  }

  EasyTierNetworkProfile _createDefaultProfile() {
    return createProfile(name: '默认网络', config: _defaultConfig());
  }

  EasyTierConfig _defaultConfig() {
    return EasyTierConfig(
      instanceName: 'ruoqing_vpn',
      networkName: 'default_network',
      networkSecret: '',
      dhcp: false,
      ipv4: '',
      peers: const <String>[],
      listeners: const <String>[],
      enableP2p: true,
      hostname: 'ruoqing_vpn',
    );
  }
}
