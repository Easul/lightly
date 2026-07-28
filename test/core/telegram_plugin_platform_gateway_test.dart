import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/telegram/telegram_plugin_platform_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('telegram_plugin_gateway_test');
  late TelegramPluginPlatformGateway gateway;
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'connect' => true,
            'createClient' => 42,
            _ => null,
          };
        });
    gateway = TelegramPluginPlatformGateway(channel: channel);
  });

  tearDown(() async {
    await gateway.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps typed client operations to the native plugin channel', () async {
    expect(await gateway.connect(), isTrue);
    expect(await gateway.createClient(), 42);
    await gateway.send(
      clientId: 42,
      requestJson: '{"@type":"getAuthorizationState"}',
    );

    expect(calls.map((call) => call.method), <String>[
      'connect',
      'createClient',
      'send',
    ]);
    expect(calls.last.arguments, <String, Object?>{
      'clientId': 42,
      'requestJson': '{"@type":"getAuthorizationState"}',
    });
  });

  test('forwards TDLib results and disconnect notifications', () async {
    final result = Completer<String>();
    final disconnected = Completer<void>();
    gateway.results.first.then(result.complete);
    gateway.disconnects.first.then((_) => disconnected.complete());

    await _sendPlatformCall(
      channel,
      const MethodCall('onResult', '{"@type":"ok","@client_id":42}'),
    );
    await _sendPlatformCall(channel, const MethodCall('onDisconnected'));

    expect(await result.future, '{"@type":"ok","@client_id":42}');
    await disconnected.future;
  });
}

Future<void> _sendPlatformCall(MethodChannel channel, MethodCall call) {
  final message = const StandardMethodCodec().encodeMethodCall(call);
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel.name, message, (_) {});
}
