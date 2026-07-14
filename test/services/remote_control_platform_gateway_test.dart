import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/services/remote_control_platform_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('remote_control_gateway_test');
  final gateway = RemoteControlPlatformGateway(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps receiver startup arguments to the platform channel', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          capturedCall = call;
          return true;
        });

    final started = await gateway.startReceiver(
      controlPort: 18080,
      screenPort: 18081,
      screenFps: 12,
      screenBitrate: 2500000,
    );

    expect(started, isTrue);
    expect(capturedCall?.method, 'startReceiver');
    expect(capturedCall?.arguments, <String, Object?>{
      'controlPort': 18080,
      'screenPort': 18081,
      'screenFps': 12,
      'screenBitrate': 2500000,
    });
  });

  test('passes binary screen frames without JSON or base64 encoding', () async {
    MethodCall? capturedCall;
    final data = Uint8List.fromList(<int>[1, 2, 3]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          capturedCall = call;
          return null;
        });

    await gateway.pushScreenFrame(
      textureId: 7,
      data: data,
      type: 1,
      timestamp: 9,
    );

    final arguments = capturedCall?.arguments as Map<Object?, Object?>;
    expect(capturedCall?.method, 'pushScreenFrame');
    expect(arguments['textureId'], 7);
    expect(arguments['data'], data);
    expect(arguments['type'], 1);
    expect(arguments['timestamp'], 9);
  });

  test('normalizes screen info keys for Dart services', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <Object?, Object?>{1: 'value', 'width': 1080};
        });

    final info = await gateway.getScreenInfo();

    expect(info, <String, Object?>{'1': 'value', 'width': 1080});
  });
}
