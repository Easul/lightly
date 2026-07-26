import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/video/infrastructure/floating_video_platform_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('floating_video_gateway_test');
  const gateway = FloatingVideoPlatformGateway(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps keep-screen-on state to the platform channel', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          capturedCall = call;
          return true;
        });

    await gateway.setKeepScreenOn(true);

    expect(capturedCall?.method, 'keepScreenOn');
    expect(capturedCall?.arguments, <String, Object?>{'keepOn': true});
  });
}
