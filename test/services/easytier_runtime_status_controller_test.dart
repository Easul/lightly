import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/easytier/domain/easytier_config.dart';
import 'package:lightly/features/easytier/application/easytier_runtime_status_controller.dart';

void main() {
  group('EasyTierRuntimeStatusController', () {
    test('loadStatus returns next ip and restart hint', () async {
      final controller = EasyTierRuntimeStatusController(
        startVpn: (_) async => true,
        startNoTun: (_) async => true,
        stopVpn: () async {},
        getNetworkInfo: () async => <String, dynamic>{
          'map': <String, dynamic>{
            'demo': <String, dynamic>{
              'my_node_info': <String, dynamic>{
                'virtual_ipv4': <String, dynamic>{
                  'address': <String, dynamic>{'addr': 0x0A7E7E16},
                  'network_length': 24,
                },
              },
            },
          },
        },
        readLastError: () => null,
      );

      final result = await controller.loadStatus(
        instanceName: 'demo',
        previousIp: null,
      );

      expect(result.nextIp, '10.126.126.22/24');
      expect(result.shouldRestartServices, isTrue);
      expect(result.errorMessage, isNull);
    });

    test('startVpn surfaces failure and success states', () async {
      final successController = EasyTierRuntimeStatusController(
        startVpn: (_) async => true,
        startNoTun: (_) async => true,
        stopVpn: () async {},
        getNetworkInfo: () async => null,
        readLastError: () => null,
      );
      final failureController = EasyTierRuntimeStatusController(
        startVpn: (_) async => false,
        startNoTun: (_) async => false,
        stopVpn: () async {},
        getNetworkInfo: () async => null,
        readLastError: () => 'boom',
      );

      final config = EasyTierConfig(
        instanceName: 'vpn',
        networkName: 'network',
        networkSecret: '',
        dhcp: false,
        ipv4: '',
        peers: const <String>[],
        listeners: const <String>[],
        enableP2p: true,
        hostname: '',
      );

      final success = await successController.startVpn(
        config,
        useNoTunMode: false,
      );
      final failure = await failureController.startVpn(
        config,
        useNoTunMode: false,
      );

      expect(success.isRunning, isTrue);
      expect(success.shouldLoadStatus, isTrue);
      expect(failure.isRunning, isFalse);
      expect(failure.errorMessage, 'boom');
    });

    test('stopVpn returns stop state and error state', () async {
      final successController = EasyTierRuntimeStatusController(
        startVpn: (_) async => true,
        startNoTun: (_) async => true,
        stopVpn: () async {},
        getNetworkInfo: () async => null,
        readLastError: () => null,
      );
      final failureController = EasyTierRuntimeStatusController(
        startVpn: (_) async => true,
        startNoTun: (_) async => true,
        stopVpn: () async => throw Exception('stop failed'),
        getNetworkInfo: () async => null,
        readLastError: () => null,
      );

      final success = await successController.stopVpn();
      final failure = await failureController.stopVpn();

      expect(success.isRunning, isFalse);
      expect(success.clearNetworkInfo, isTrue);
      expect(failure.isRunning, isTrue);
      expect(failure.errorMessage, contains('stop failed'));
    });
  });
}
