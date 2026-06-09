import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/models/easytier_config.dart';
import 'package:lightly/services/app_lifecycle_manager.dart';
import 'package:lightly/services/easytier_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const easyTierChannel = MethodChannel('easytier_vpn');

  tearDown(() async {
    await EasyTierService().stopVpn();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(easyTierChannel, null);
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
