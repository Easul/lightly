import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/easytier/domain/easytier_config.dart';
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
      EasyTierConfig(
        instanceName: 'receiver',
        networkName: 'network',
        portForwards: const <String>['tcp://0.0.0.0:18080/127.0.0.1:18080'],
        portMappings: const <EasyTierPortMapping>[
          EasyTierPortMapping(port: 18080),
        ],
      ),
    );

    expect(success, isTrue);
    expect(arguments?['useAndroidVpn'], isFalse);
    expect(arguments?['config'], contains('no_tun = true'));
    expect(arguments?['config'], contains('enable_kcp_proxy = true'));
    expect(arguments?['config'], contains('enable_quic_proxy = true'));
    expect(arguments?['config'], contains('enable_socks5 = true'));
    final activeSocksPort = EasyTierService().activeNoTunSocksPort;
    expect(activeSocksPort, isNotNull);
    expect(activeSocksPort, inInclusiveRange(11080, 11120));
    expect(arguments?['config'], contains('socks5_port = $activeSocksPort'));
    expect(
      arguments?['config'],
      contains('socks5_proxy = "socks5://0.0.0.0:$activeSocksPort"'),
    );
    expect(
      arguments?['config'],
      isNot(contains('bind_addr = "0.0.0.0:18080"')),
    );
    expect(
      arguments?['config'],
      isNot(contains('dst_addr = "127.0.0.1:18080"')),
    );
    expect(
      arguments?['config'],
      isNot(contains('bind_addr = "0.0.0.0:18088"')),
    );
    expect(
      arguments?['config'],
      isNot(contains('dst_addr = "127.0.0.1:18088"')),
    );
    expect(arguments?['config'], isNot(contains('[[port_forward]]')));
    expect(EasyTierService().isNoTunMode, isTrue);
    expect(EasyTierService().usesAndroidVpn, isFalse);
    expect(EasyTierService().activeNoTunSocksPort, activeSocksPort);
  });

  test('startNoTun preserves custom SOCKS port', () async {
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
      EasyTierConfig(
        instanceName: 'receiver-custom',
        networkName: 'network',
        socks5Port: 11180,
      ),
    );

    expect(success, isTrue);
    expect(arguments?['config'], contains('enable_socks5 = true'));
    expect(arguments?['config'], contains('socks5_port = 11180'));
    expect(
      arguments?['config'],
      contains('socks5_proxy = "socks5://0.0.0.0:11180"'),
    );
    expect(EasyTierService().activeNoTunSocksPort, 11180);
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
