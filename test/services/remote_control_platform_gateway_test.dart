import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/infrastructure/remote_control_platform_gateway.dart';

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

  test('maps the remaining remote-control commands', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'startController' ||
            'showDisconnectOverlay' ||
            'checkAccessibilityPermission' ||
            'startScreenCapture' => true,
            'createScreenTexture' => 42,
            _ => null,
          };
        });

    expect(await gateway.startController('10.126.126.2'), isTrue);
    await gateway.stop();
    await gateway.executeCommand('{"type":"global"}');
    expect(await gateway.showDisconnectOverlay('disconnected'), isTrue);
    expect(await gateway.checkAccessibilityPermission(), isTrue);
    await gateway.openAccessibilitySettings();
    expect(await gateway.startScreenCapture(fps: 12, bitrate: 2500000), isTrue);
    await gateway.stopScreenCapture();
    await gateway.requestKeyFrame();
    await gateway.updateBitrate(1800000);
    expect(await gateway.createScreenTexture(width: 1080, height: 2340), 42);
    await gateway.disposeScreenTexture(42);

    expect(
      calls
          .map(
            (call) => <String, Object?>{
              'method': call.method,
              'arguments': call.arguments,
            },
          )
          .toList(),
      <Map<String, Object?>>[
        <String, Object?>{
          'method': 'startController',
          'arguments': <String, Object?>{'host': '10.126.126.2'},
        },
        <String, Object?>{'method': 'stop', 'arguments': null},
        <String, Object?>{
          'method': 'executeCommand',
          'arguments': <String, Object?>{'command': '{"type":"global"}'},
        },
        <String, Object?>{
          'method': 'showDisconnectOverlay',
          'arguments': <String, Object?>{'message': 'disconnected'},
        },
        <String, Object?>{
          'method': 'checkAccessibilityPermission',
          'arguments': null,
        },
        <String, Object?>{
          'method': 'openAccessibilitySettings',
          'arguments': null,
        },
        <String, Object?>{
          'method': 'startScreenCapture',
          'arguments': <String, Object?>{'fps': 12, 'bitrate': 2500000},
        },
        <String, Object?>{'method': 'stopScreenCapture', 'arguments': null},
        <String, Object?>{'method': 'requestKeyFrame', 'arguments': null},
        <String, Object?>{
          'method': 'updateBitrate',
          'arguments': <String, Object?>{'bitrate': 1800000},
        },
        <String, Object?>{
          'method': 'createScreenTexture',
          'arguments': <String, Object?>{'width': 1080, 'height': 2340},
        },
        <String, Object?>{
          'method': 'disposeScreenTexture',
          'arguments': <String, Object?>{'textureId': 42},
        },
      ],
    );
  });
}
