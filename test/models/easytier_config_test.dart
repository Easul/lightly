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

    test('toToml emits no-tun and proxy acceleration flags', () {
      final config = EasyTierConfig(
        instanceName: 'vpn',
        networkName: 'network',
        noTun: true,
        enableKcpProxy: true,
        enableQuicProxy: true,
        portForwards: const <String>['tcp://0.0.0.0:18080/10.126.126.1:18080'],
        portMappings: const <EasyTierPortMapping>[
          EasyTierPortMapping(port: 8080, remark: 'NAS'),
        ],
      );

      final toml = config.toToml();

      expect(toml, contains('no_tun = true'));
      expect(toml, contains('enable_kcp_proxy = true'));
      expect(toml, contains('enable_quic_proxy = true'));
      expect(
        toml,
        contains(
          'port_forward = ["tcp://0.0.0.0:18080/10.126.126.1:18080", "tcp://0.0.0.0:8080/127.0.0.1:8080"]',
        ),
      );
    });

    test('json preserves structured port mappings', () {
      final config = EasyTierConfig(
        instanceName: 'vpn',
        networkName: 'network',
        portMappings: const <EasyTierPortMapping>[
          EasyTierPortMapping(port: 3001, remark: '文件服务'),
        ],
      );

      final restored = EasyTierConfig.fromJson(config.toJson());

      expect(restored.portMappings.single.port, 3001);
      expect(restored.portMappings.single.remark, '文件服务');
    });
  });
}
