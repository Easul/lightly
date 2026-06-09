import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/models/easytier_config.dart';
import 'package:lightly/models/remote_control_config.dart';
import 'package:lightly/services/app_lifecycle_manager.dart';
import 'package:lightly/services/easytier_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const easyTierChannel = MethodChannel('easytier_vpn');

  tearDown(() async {
    await EasyTierService().stopVpn();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(easyTierChannel, null);
  });

  test('controller no-vpn prepares local forwards to target peer', () async {
    SharedPreferences.setMockInitialValues({});
    Map<dynamic, dynamic>? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(easyTierChannel, (call) async {
          if (call.method == 'startVpn') {
            arguments = Map<dynamic, dynamic>.from(call.arguments as Map);
            return true;
          }
          if (call.method == 'stopVpn') {
            return true;
          }
          return null;
        });

    final forwardPlan = await AppLifecycleManager()
        .ensureNoTunForRemoteControlTarget(
          targetHost: '10.126.126.2',
          candidatePorts: const <RemoteControlPortConfig>[
            RemoteControlPortConfig(controlPort: 18080, screenPort: 18081),
          ],
        );

    expect(forwardPlan, isNotNull);
    expect(arguments?['useAndroidVpn'], isFalse);
    expect(arguments?['config'], contains('bind_addr = "127.0.0.1:19080"'));
    expect(arguments?['config'], contains('dst_addr = "10.126.126.2:18080"'));
    expect(arguments?['config'], contains('bind_addr = "127.0.0.1:19081"'));
    expect(arguments?['config'], contains('dst_addr = "10.126.126.2:18081"'));
    expect(
      forwardPlan!.localPortsFor(
        const RemoteControlPortConfig(controlPort: 18080, screenPort: 18081),
      ),
      isA<RemoteControlPortConfig>()
          .having((ports) => ports.controlPort, 'controlPort', 19080)
          .having((ports) => ports.screenPort, 'screenPort', 19081),
    );
  });

  test(
    'receiver no-vpn reuses an already running P2P no-vpn instance',
    () async {
      var startCalls = 0;
      var stopCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(easyTierChannel, (call) async {
            if (call.method == 'startVpn') {
              startCalls += 1;
              return true;
            }
            if (call.method == 'stopVpn') {
              stopCalls += 1;
              return true;
            }
            return null;
          });

      await EasyTierService().startNoTun(
        EasyTierConfig(instanceName: 'vpn', networkName: 'network'),
      );
      final reused = await AppLifecycleManager().ensureVpnForRemoteControl(
        noTunMode: true,
      );

      expect(reused, isTrue);
      expect(startCalls, 1);
      expect(stopCalls, 0);
    },
  );
}
