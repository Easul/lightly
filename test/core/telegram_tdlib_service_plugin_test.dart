import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/core/network/local_proxy_endpoint_provider.dart';
import 'package:lightly/core/platform/platform_channel_names.dart';
import 'package:lightly/features/telegram/telegram_checkin_models.dart';
import 'package:lightly/features/telegram/telegram_tdlib_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initializes TDLib through the native plugin JSON contract', () async {
    const channel = MethodChannel(PlatformChannelNames.telegramPlugin);
    final requests = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'connect':
              return true;
            case 'createClient':
              return 42;
            case 'send':
              final arguments = (call.arguments as Map)
                  .cast<Object?, Object?>();
              final request =
                  jsonDecode(arguments['requestJson']! as String)
                      as Map<String, dynamic>;
              requests.add(request);
              final responseType = switch (request['@type']) {
                'getAuthorizationState' =>
                  'authorizationStateWaitTdlibParameters',
                'setTdlibParameters' => 'ok',
                'addProxy' => 'proxy',
                _ => 'ok',
              };
              unawaited(
                _sendPluginResult(channel, <String, Object?>{
                  '@type': responseType,
                  '@extra': request['@extra'],
                  '@client_id': 42,
                }),
              );
              return null;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = TelegramTdlibService.instance;
    final originalProxy = service.proxyEndpointProvider;
    addTearDown(() => service.proxyEndpointProvider = originalProxy);
    service.proxyEndpointProvider = const _ProxyEndpoint(23333);

    await service.start(
      const TelegramCheckinConfig(
        apiId: 12345,
        apiHash: 'test-hash',
        phoneNumber: '+8613800000000',
      ),
    );

    expect(requests.map((request) => request['@type']), <String>[
      'getAuthorizationState',
      'setTdlibParameters',
      'addProxy',
    ]);
    final parameters = requests[1];
    expect(parameters['api_id'], 12345);
    expect(parameters['api_hash'], 'test-hash');
    expect(parameters['database_directory'], isEmpty);
    expect(parameters['files_directory'], isEmpty);
    expect(requests[2]['port'], 23333);
    expect(service.proxyStatus.value, '已使用本地代理 127.0.0.1:23333');

    await _sendPluginResult(channel, <String, Object?>{
      '@type': 'updateAuthorizationState',
      '@client_id': 42,
      'authorization_state': <String, Object?>{
        '@type': 'authorizationStateWaitPhoneNumber',
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(service.authStep.value, TelegramAuthStep.phone);
  });
}

class _ProxyEndpoint implements LocalProxyEndpointProvider {
  const _ProxyEndpoint(this.localSocks5Port);

  @override
  final int? localSocks5Port;
}

Future<void> _sendPluginResult(
  MethodChannel channel,
  Map<String, Object?> result,
) {
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall('onResult', jsonEncode(result)),
  );
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel.name, message, (_) {});
}
