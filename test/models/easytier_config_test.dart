import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/models/easytier_config.dart';

void main() {
  group('EasyTierConfig', () {
    test('toToml emits only the selected active peer', () {
      final config = EasyTierConfig(
        instanceName: 'vpn',
        networkName: 'network',
        peers: const <String>[
          'tcp://first.example.com:11010',
          'tcp://second.example.com:11010',
        ],
        activePeerIndex: 1,
      );

      final toml = config.toToml();

      expect(toml, isNot(contains('tcp://first.example.com:11010')));
      expect(toml, contains('uri = "tcp://second.example.com:11010"'));
      expect('[[peer]]'.allMatches(toml), hasLength(1));
    });

    test('json preserves peer remarks and active peer index', () {
      final config = EasyTierConfig(
        instanceName: 'vpn',
        networkName: 'network',
        peers: const <String>['tcp://peer.example.com:11010'],
        peerRemarks: const <String>['家里主节点'],
        activePeerIndex: 0,
      );

      final restored = EasyTierConfig.fromJson(config.toJson());

      expect(restored.peers, config.peers);
      expect(restored.peerRemarks, config.peerRemarks);
      expect(restored.activePeerIndex, 0);
    });
  });
}
