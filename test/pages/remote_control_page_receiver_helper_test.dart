import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/remote_control_page_receiver_helper.dart';
import 'package:lightly/services/remote_control_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('remote_control');
  const webRtcChannel = MethodChannel('FlutterWebRTC.Method');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'checkAccessibilityPermission':
            case 'startReceiver':
            case 'startScreenCapture':
            case 'stopScreenCapture':
            case 'stop':
              return true;
            case 'getScreenInfo':
              return <String, Object?>{
                'width': 1080,
                'height': 1920,
                'density': 2.5,
              };
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(webRtcChannel, (call) async => true);
  });

  tearDown(() async {
    await RemoteControlService().shutdownReceiverHostResources();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(webRtcChannel, null);
  });

  test('no-tun receiver flow starts with voice disabled', () async {
    bool? capturedNoTunMode;
    final ports = await const RemoteControlPageReceiverHelper()
        .startReceiverFlow(
          channel: channel,
          service: RemoteControlService(),
          useNoTunMode: true,
          ensureVpnForRemoteControl: ({bool noTunMode = false}) async {
            capturedNoTunMode = noTunMode;
            return true;
          },
        );

    expect(capturedNoTunMode, isTrue);
    expect(ports.controlPort, greaterThan(0));
    expect(RemoteControlService().isVoiceEnabled, isFalse);
  });
}
