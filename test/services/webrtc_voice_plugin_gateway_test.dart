import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/domain/remote_control_protocol.dart';
import 'package:lightly/features/remote_control/infrastructure/webrtc_voice_plugin_platform_gateway.dart';
import 'package:lightly/features/remote_control/infrastructure/webrtc_voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('correlates native plugin JSON responses', () async {
    const channel = MethodChannel('webrtc_voice_plugin_gateway_test');
    final gateway = WebRtcVoicePluginPlatformGateway(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'connect' ||
              call.method == 'requestAudioPermission') {
            return true;
          }
          if (call.method == 'request') {
            final arguments = (call.arguments as Map).cast<Object?, Object?>();
            final request =
                jsonDecode(arguments['requestJson']! as String)
                    as Map<String, dynamic>;
            unawaited(
              _sendPluginEvent(channel, <String, Object?>{
                'type': 'result',
                'requestId': request['requestId'],
                'data': <String, Object?>{'prepared': true},
              }),
            );
          }
          return null;
        });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await gateway.dispose();
    });

    expect(await gateway.connect(), isTrue);
    expect(await gateway.requestAudioPermission(), isTrue);
    expect((await gateway.request('getState'))['prepared'], isTrue);
  });

  test(
    'voice service forwards plugin signaling without Flutter WebRTC',
    () async {
      const channel = MethodChannel('webrtc_voice_service_plugin_test');
      final gateway = WebRtcVoicePluginPlatformGateway(channel: channel);
      final sentSignals = <StatusMessage>[];
      final logs = <String>[];
      final service = WebRtcVoiceService(
        plugin: gateway,
        sendSignal: (message) async => sentSignals.add(message),
        ensureDiagnosticsLogging: () async {},
        log: (message, {error}) => logs.add(message),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'connect' ||
                call.method == 'requestAudioPermission') {
              return true;
            }
            if (call.method == 'request') {
              final arguments = (call.arguments as Map)
                  .cast<Object?, Object?>();
              final request =
                  jsonDecode(arguments['requestJson']! as String)
                      as Map<String, dynamic>;
              unawaited(
                _sendPluginEvent(channel, <String, Object?>{
                  'type': 'result',
                  'requestId': request['requestId'],
                  'data': <String, Object?>{},
                }),
              );
            }
            return null;
          });
      addTearDown(() async {
        await service.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await gateway.dispose();
      });

      await service.prepare(isController: true);
      await _sendPluginEvent(channel, <String, Object?>{
        'type': 'signal',
        'action': 'webrtc_candidate',
        'data': <String, Object?>{
          'candidate': 'candidate:1 1 udp 1 192.168.1.10 45678 typ host',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(service.isPrepared, isTrue);
      expect(sentSignals.single.action, 'webrtc_candidate');
      expect(
        sentSignals.single.data['candidate'],
        'candidate:1 1 udp 1 192.168.1.10 45678 typ host',
      );
      expect(logs, contains(startsWith('webrtc-local-candidate:')));
    },
  );
}

Future<void> _sendPluginEvent(
  MethodChannel channel,
  Map<String, Object?> event,
) {
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall('onEvent', jsonEncode(event)),
  );
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel.name, message, (_) {});
}
