import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/models/easytier_config.dart';
import 'package:lightly/services/easytier_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('easytier_vpn');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('startNoTun starts EasyTier instance without Android VPN', () async {
    Map<dynamic, dynamic>? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'startVpn') {
            arguments = Map<dynamic, dynamic>.from(call.arguments as Map);
            return true;
          }
          return null;
        });

    final success = await EasyTierService().startNoTun(
      EasyTierConfig(instanceName: 'receiver', networkName: 'network'),
    );

    expect(success, isTrue);
    expect(arguments?['useAndroidVpn'], isFalse);
    expect(arguments?['config'], contains('no_tun = true'));
    expect(arguments?['config'], contains('enable_kcp_proxy = true'));
    expect(arguments?['config'], contains('enable_quic_proxy = true'));
    expect(
      arguments?['config'],
      contains('socks5_proxy = "socks5://127.0.0.1:11080"'),
    );
    expect(arguments?['config'], contains('bind_addr = "0.0.0.0:18080"'));
    expect(arguments?['config'], contains('dst_addr = "127.0.0.1:18080"'));
    expect(arguments?['config'], contains('bind_addr = "0.0.0.0:18088"'));
    expect(arguments?['config'], contains('dst_addr = "127.0.0.1:18088"'));
    expect(EasyTierService().isNoTunMode, isTrue);
    expect(EasyTierService().usesAndroidVpn, isFalse);
    expect(EasyTierService().activeNoTunSocksPort, 11080);
  });

  test('startVpn tracks Android VPN runtime mode', () async {
    Map<dynamic, dynamic>? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'startVpn') {
            arguments = Map<dynamic, dynamic>.from(call.arguments as Map);
            return true;
          }
          return null;
        });

    final success = await EasyTierService().startVpn(
      EasyTierConfig(instanceName: 'vpn', networkName: 'network'),
    );

    expect(success, isTrue);
    expect(arguments?['useAndroidVpn'], isTrue);
    expect(EasyTierService().isNoTunMode, isFalse);
    expect(EasyTierService().usesAndroidVpn, isTrue);
  });
}
