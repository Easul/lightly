import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_platform_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('browser_platform_gateway_test');
  final gateway = BrowserPlatformGateway(channel: channel);
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('checks WebView proxy override support', () async {
    expect(await gateway.isProxyOverrideSupported(), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'isSupported');
    expect(calls.single.arguments, isNull);
  });

  test('maps proxy arguments to the platform contract', () async {
    final applied = await gateway.setProxy(
      host: '127.0.0.1',
      port: 23333,
      scheme: 'http',
      bypassDomains: const <String>['example.com'],
    );

    expect(applied, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'setProxy');
    expect(calls.single.arguments, <String, Object?>{
      'host': '127.0.0.1',
      'port': 23333,
      'scheme': 'http',
      'bypassDomains': <String>['example.com'],
    });
  });

  test('clears the WebView proxy override', () async {
    expect(await gateway.clearProxy(), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'clearProxy');
    expect(calls.single.arguments, isNull);
  });
}
