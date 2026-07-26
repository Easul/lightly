import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/models/remote_control_config.dart';
import 'package:lightly/features/remote_control/domain/remote_control_protocol.dart';
import 'package:lightly/services/remote_control_platform_gateway.dart';
import 'package:lightly/services/remote_control_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(RemoteControlPlatformGateway.channelName);
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

  test(
    'proxy discovery preserves status bytes received with socks response',
    () async {
      final service = RemoteControlService();
      final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final status = StatusMessage.portConfig(
        controlPort: 18080,
        screenPort: 18081,
      );
      final statusBytes = utf8.encode('${RemoteControlCodec.encode(status)}\n');

      proxy.listen((client) {
        unawaited(() async {
          final iterator = StreamIterator<List<int>>(client);
          await iterator.moveNext();
          client.add(const <int>[0x05, 0x00]);
          await client.flush();
          await iterator.moveNext();
          client.add(<int>[
            0x05,
            0x00,
            0x00,
            0x01,
            127,
            0,
            0,
            1,
            0,
            0,
            ...statusBytes,
          ]);
          await client.flush();
          await iterator.cancel();
        }());
      });

      try {
        final discovered = await service.discoverReceiverPorts(
          '10.126.126.2',
          useProxy: true,
          proxyPort: proxy.port,
        );

        expect(discovered?.controlPort, 18080);
        expect(discovered?.screenPort, 18081);
      } finally {
        await proxy.close();
      }
    },
  );
}
