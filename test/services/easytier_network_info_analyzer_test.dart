import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/easytier/application/easytier_network_info_analyzer.dart';

void main() {
  group('EasyTierNetworkInfoAnalyzer', () {
    const instanceName = 'demo';

    final networkInfo = <String, dynamic>{
      'map': <String, dynamic>{
        instanceName: <String, dynamic>{
          'my_node_info': <String, dynamic>{
            'virtual_ipv4': <String, dynamic>{
              'address': <String, dynamic>{'addr': 0x0A7E7E16},
              'network_length': 24,
            },
            'stun_info': <String, dynamic>{
              'udp_nat_type': 'Open',
              'tcp_nat_type': 'Open',
            },
          },
          'routes': <dynamic>[
            <String, dynamic>{
              'peer_id': 1,
              'hostname': 'peer-a',
              'cost': 1,
              'next_hop_peer_id': 1,
              'path_latency': 12,
              'ipv4_addr': <String, dynamic>{
                'address': <String, dynamic>{'addr': 0x0A7E7E17},
                'network_length': 24,
              },
            },
            <String, dynamic>{
              'peer_id': 2,
              'hostname': 'peer-b',
              'cost': 2,
              'next_hop_peer_id': 1,
              'path_latency': 48,
              'ipv4_addr': <String, dynamic>{
                'address': <String, dynamic>{'addr': 0x0A7E7E18},
                'network_length': 24,
              },
            },
          ],
          'peers': <dynamic>[
            <String, dynamic>{
              'peer_id': 1,
              'directly_connected_conns': <dynamic>['x'],
            },
            <String, dynamic>{
              'peer_id': 2,
              'directly_connected_conns': <dynamic>[],
            },
          ],
          'events': <dynamic>[
            '{"event":{"PeerConnRemoved":{"peer_id":2}}}',
            '{"event":{"PeerConnAdded":{"peer_id":2}}}',
          ],
        },
      },
    };

    test('extracts instance ipv4 from mapped payload', () {
      expect(
        EasyTierNetworkInfoAnalyzer.extractInstanceIpv4(
          networkInfo,
          instanceName,
        ),
        '10.126.126.22/24',
      );
    });

    test('builds peer summaries with direct and relay modes', () {
      final peers = EasyTierNetworkInfoAnalyzer.buildPeerSummaries(
        networkInfo,
        instanceName,
      );

      expect(peers, hasLength(2));
      expect(peers.first['name'], 'peer-a');
      expect(peers.first['mode'], '直连 (LAN)');
      expect(peers[1]['name'], 'peer-b');
      expect(peers[1]['mode'], '经 peer-a 中继');
      expect(peers[1]['status'], '最近重连');
    });

    test('builds diagnostics and formats network info', () {
      final diagnostics = EasyTierNetworkInfoAnalyzer.buildDiagnostics(
        networkInfo,
        instanceName,
      );
      final text = EasyTierNetworkInfoAnalyzer.formattedNetworkInfoText(
        rawNetworkInfo: null,
        networkInfo: networkInfo,
        instanceName: instanceName,
      );

      expect(diagnostics.first, contains('NAT 状态'));
      expect(diagnostics.last, contains('peer-b 当前走中继路径'));
      expect(text, contains('"my_node_info"'));
    });

    test('keeps unrouted peers as status-only entries', () {
      final statusOnlyNetworkInfo = <String, dynamic>{
        'map': <String, dynamic>{
          instanceName: <String, dynamic>{
            'routes': <dynamic>[],
            'peers': <dynamic>[
              <String, dynamic>{
                'peer_id': 9,
                'hostname': 'relay-blocked',
                'directly_connected_conns': <dynamic>[],
              },
            ],
            'events': <dynamic>['{"event":{"PeerConnRemoved":{"peer_id":9}}}'],
          },
        },
      };

      final peers = EasyTierNetworkInfoAnalyzer.buildPeerSummaries(
        statusOnlyNetworkInfo,
        instanceName,
      );

      expect(peers, hasLength(1));
      expect(peers.first['name'], 'relay-blocked');
      expect(peers.first['remoteReachable'], 'false');
      expect(peers.first['status'], '已离线/中继不可用');
    });

    test('filters unnamed route and peer placeholders', () {
      final unnamedNetworkInfo = <String, dynamic>{
        'map': <String, dynamic>{
          instanceName: <String, dynamic>{
            'routes': <dynamic>[
              <String, dynamic>{
                'peer_id': 11,
                'cost': 1,
                'path_latency': 8,
                'ipv4_addr': <String, dynamic>{
                  'address': <String, dynamic>{'addr': 0x0A7E7E21},
                  'network_length': 24,
                },
              },
            ],
            'peers': <dynamic>[
              <String, dynamic>{
                'peer_id': 11,
                'directly_connected_conns': <dynamic>[],
              },
              <String, dynamic>{
                'peer_id': 12,
                'hostname': 'named-peer',
                'directly_connected_conns': <dynamic>[],
              },
            ],
            'events': <dynamic>[],
          },
        },
      };

      final peers = EasyTierNetworkInfoAnalyzer.buildPeerSummaries(
        unnamedNetworkInfo,
        instanceName,
      );

      expect(peers, hasLength(1));
      expect(peers.first['name'], 'named-peer');
      expect(peers.first['remoteReachable'], 'false');
    });
  });
}
