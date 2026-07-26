import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/easytier/infrastructure/easytier_platform_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('easytier_platform_gateway_test');
  final gateway = EasyTierPlatformGateway(channel: channel);
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'getNetworkInfo' => '{"running":true}',
            'getLastError' => 'native error',
            _ => true,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps configuration parsing arguments', () async {
    expect(await gateway.parseConfig('instance_name = "test"'), isTrue);
    expect(calls.single.method, 'parseConfig');
    expect(calls.single.arguments, <String, Object?>{
      'config': 'instance_name = "test"',
    });
  });

  test('checks Android VPN permission', () async {
    expect(await gateway.checkVpnPermission(), isTrue);
    expect(calls.single.method, 'checkVpnPermission');
    expect(calls.single.arguments, isNull);
  });

  test('maps network instance startup arguments', () async {
    expect(
      await gateway.startVpn(
        config: 'instance_name = "test"',
        instanceName: 'test',
        useAndroidVpn: false,
      ),
      isTrue,
    );
    expect(calls.single.method, 'startVpn');
    expect(calls.single.arguments, <String, Object?>{
      'config': 'instance_name = "test"',
      'instanceName': 'test',
      'useAndroidVpn': false,
    });
  });

  test('stops the network instance', () async {
    expect(await gateway.stopVpn(), isTrue);
    expect(calls.single.method, 'stopVpn');
    expect(calls.single.arguments, isNull);
  });

  test('gets raw network information', () async {
    expect(await gateway.getNetworkInfo(), '{"running":true}');
    expect(calls.single.method, 'getNetworkInfo');
    expect(calls.single.arguments, isNull);
  });

  test('gets the last native error', () async {
    expect(await gateway.getLastError(), 'native error');
    expect(calls.single.method, 'getLastError');
    expect(calls.single.arguments, isNull);
  });
}
