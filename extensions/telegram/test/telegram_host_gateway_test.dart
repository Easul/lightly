import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram/features/telegram/telegram_checkin_store.dart';
import 'package:telegram/features/telegram/telegram_host_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads host context and round-trips Lightly-owned config', () async {
    const channel = MethodChannel('telegram_host_gateway_test');
    String? savedJson;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'getHostContext' => <String, Object?>{
              'hostPackage': 'lightly.tool.profile',
              'dataAuthority': 'lightly.tool.profile.optional_plugins.data',
              'proxyPort': 23333,
            },
            'readTelegramConfig' => jsonEncode(<String, Object?>{
              'apiId': 123,
              'apiHash': 'hash',
              'phoneNumber': '+8613800000000',
              'targets': <Object?>[],
            }),
            'writeTelegramConfig' => () {
              savedJson =
                  (call.arguments as Map<Object?, Object?>)['json'] as String;
              return true;
            }(),
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final gateway = TelegramHostGateway(channel: channel);
    addTearDown(gateway.context.dispose);
    await gateway.initialize();
    final store = TelegramCheckinStore(gateway: gateway);

    final config = await store.load();
    await store.save(config.copyWith(phoneNumber: '+8613900000000'));

    expect(gateway.context.value.hostPackage, 'lightly.tool.profile');
    expect(gateway.context.value.proxyPort, 23333);
    expect(config.apiId, 123);
    expect(
      (jsonDecode(savedJson!) as Map<String, dynamic>)['phoneNumber'],
      '+8613900000000',
    );
  });
}
