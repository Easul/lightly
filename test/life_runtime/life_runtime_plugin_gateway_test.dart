import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/life_runtime/infrastructure/life_runtime_plugin_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encodes fixed service options and decodes status', () async {
    const channel = MethodChannel('life_runtime_plugin_gateway_test');
    final calls = <MethodCall>[];
    final gateway = LifeRuntimePluginGateway(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'start') return '{"service":"mindgit"}';
          if (call.method == 'status') {
            return jsonEncode(<String, Object?>{
              'running': <String, Object?>{},
            });
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(
      await gateway.start(
        'mindgit',
        host: '0.0.0.0',
        allowLan: true,
        port: 8787,
      ),
      contains('mindgit'),
    );
    expect(calls.single.method, 'start');
    final arguments = (calls.single.arguments as Map).cast<String, Object?>();
    expect(arguments['serviceId'], 'mindgit');
    expect(jsonDecode(arguments['optionsJson']! as String), <String, Object?>{
      'root': './',
      'host': '0.0.0.0',
      'allowLan': true,
      'port': 8787,
    });

    expect(await gateway.status(), <String, Object?>{
      'running': <String, Object?>{},
    });
  });
}
