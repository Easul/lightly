import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/models/remote_control_config.dart';
import 'package:lightly/services/remote_control_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('remote_control');
  const webRtcChannel = MethodChannel('FlutterWebRTC.Method');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'startReceiver':
            case 'stop':
              return true;
            case 'showDisconnectOverlay':
              return true;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(webRtcChannel, (call) async {
          return true;
        });
  });

  tearDown(() async {
    await RemoteControlService().disconnect();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(webRtcChannel, null);
  });

  test('receiver port discovery probe does not become a session', () async {
    final service = RemoteControlService();
    final ports = await RemoteControlPortConfig.detectAvailable();

    await service.startReceiver(
      config: RemoteControlConfig(
        ports: ports,
        enableScreen: false,
        enableVoice: false,
      ),
    );

    expect(service.state, RemoteControlState.idle);

    final discovered = await service.discoverReceiverPorts('127.0.0.1');

    expect(discovered?.controlPort, ports.controlPort);
    expect(discovered?.screenPort, ports.screenPort);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(service.state, RemoteControlState.idle);
  });
}
