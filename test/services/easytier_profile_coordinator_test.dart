import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/models/easytier_config.dart';
import 'package:lightly/models/easytier_network_profile.dart';
import 'package:lightly/services/easytier_profile_coordinator.dart';
import 'package:lightly/services/easytier_profile_service.dart';

void main() {
  group('EasyTierProfileCoordinator', () {
    late _FakeEasyTierProfileService service;
    late EasyTierProfileCoordinator coordinator;

    setUp(() {
      service = _FakeEasyTierProfileService();
      coordinator = EasyTierProfileCoordinator(profileService: service);
    });

    test('loadProfiles returns selected profile from service', () async {
      service.profiles = [
        service.makeProfile('1', 'one'),
        service.makeProfile('2', 'two'),
      ];
      service.selectedId = '2';

      final result = await coordinator.loadProfiles();

      expect(result.profiles, hasLength(2));
      expect(result.selectedProfile.id, '2');
    });

    test('persistCurrentProfile updates selected profile and saves', () async {
      final profiles = [service.makeProfile('1', 'old')];
      final config = EasyTierConfig(
        instanceName: 'vpn',
        networkName: 'new-name',
        networkSecret: '',
        dhcp: false,
        ipv4: '',
        peers: <String>[],
        listeners: <String>[],
        enableP2p: true,
        hostname: '',
      );

      final result = await coordinator.persistCurrentProfile(
        selectedId: '1',
        profiles: profiles,
        currentConfig: config,
      );

      expect(result, isNotNull);
      expect(result!.selectedProfile.name, 'new-name');
      expect(service.savedProfiles.single.name, 'new-name');
    });

    test('create and delete profile update selection', () async {
      service.profiles = [service.makeProfile('1', 'one')];

      final created = await coordinator.createProfile(
        profiles: service.profiles,
      );
      expect(created.profiles, hasLength(2));
      expect(service.selectedId, created.selectedProfile.id);

      final deleted = await coordinator.deleteCurrentProfile(
        selectedProfileId: created.selectedProfile.id,
        profiles: created.profiles,
      );
      expect(deleted, isNotNull);
      expect(deleted!.profiles, hasLength(1));
      expect(service.selectedId, deleted.selectedProfile.id);
    });
  });
}

class _FakeEasyTierProfileService extends EasyTierProfileService {
  List<EasyTierNetworkProfile> profiles = [];
  String? selectedId;
  List<EasyTierNetworkProfile> savedProfiles = [];

  EasyTierNetworkProfile makeProfile(String id, String name) {
    final now = DateTime(2024);
    return EasyTierNetworkProfile(
      id: id,
      name: name,
      config: EasyTierConfig(
        instanceName: 'vpn',
        networkName: 'network',
        networkSecret: '',
        dhcp: false,
        ipv4: '',
        peers: <String>[],
        listeners: <String>[],
        enableP2p: true,
        hostname: '',
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<List<EasyTierNetworkProfile>> loadProfiles() async => profiles;

  @override
  Future<void> saveProfiles(List<EasyTierNetworkProfile> profiles) async {
    savedProfiles = profiles;
    this.profiles = profiles;
  }

  @override
  Future<String?> getSelectedProfileId() async => selectedId;

  @override
  Future<void> setSelectedProfileId(String id) async {
    selectedId = id;
  }

  @override
  EasyTierNetworkProfile createProfile({String? name, EasyTierConfig? config}) {
    return makeProfile('created-${profiles.length + 1}', name ?? 'new');
  }
}
