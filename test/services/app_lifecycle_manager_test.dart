import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/models/easytier_config.dart';
import 'package:lightly/services/app_lifecycle_manager.dart';
import 'package:lightly/services/easytier_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const easyTierChannel = MethodChannel('easytier_vpn');
  const remoteControlChannel = MethodChannel('remote_control');
  const webRtcChannel = MethodChannel('FlutterWebRTC.Method');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(webRtcChannel, (call) async => true);
  });

  tearDown(() async {
    await EasyTierService().stopVpn();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(easyTierChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(remoteControlChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(webRtcChannel, null);
  });

  test('receiver no-vpn startup does not add port forwards', () async {
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

    final started = await AppLifecycleManager().ensureVpnForRemoteControl(
      noTunMode: true,
    );

    expect(started, isTrue);
    expect(arguments?['useAndroidVpn'], isFalse);
    expect(arguments?['config'], isNot(contains('[[port_forward]]')));
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

  test(
    'shutdownAllServices stops no-vpn EasyTier even when native stop throws',
    () async {
      var stopCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(easyTierChannel, (call) async {
            if (call.method == 'startVpn') {
              return true;
            }
            if (call.method == 'stopVpn') {
              stopCalls += 1;
              return true;
            }
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(remoteControlChannel, (call) async {
            if (call.method == 'stop') {
              throw PlatformException(code: 'stop-failed');
            }
            if (call.method == 'stopScreenCapture') {
              return true;
            }
            return null;
          });

      await EasyTierService().startNoTun(
        EasyTierConfig(instanceName: 'vpn', networkName: 'network'),
      );

      await AppLifecycleManager().shutdownAllServices();
      await AppLifecycleManager().shutdownAllServices();

      expect(stopCalls, 2);
      expect(EasyTierService().isRunning, isFalse);
    },
  );
}
