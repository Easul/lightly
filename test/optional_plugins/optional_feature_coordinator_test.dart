import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/app/optional_feature_coordinator.dart';
import 'package:lightly/core/network/local_proxy_endpoint_provider.dart';
import 'package:lightly/features/optional_plugins/infrastructure/optional_plugin_platform_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('launches Telegram plugin with the current local SOCKS5 port', () async {
    const channel = MethodChannel('optional_plugin_launch_test');
    Map<Object?, Object?>? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          arguments = (call.arguments as Map).cast<Object?, Object?>();
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final coordinator = OptionalFeatureCoordinator(
      platformGateway: OptionalPluginPlatformGateway(channel: channel),
      localProxyEndpoint: const _FakeLocalProxyEndpoint(23333),
    );

    expect(await coordinator.launchTelegramPlugin(), isTrue);
    expect(arguments?['packageName'], 'lightly.tool.plugin.telegram');
    expect(
      (arguments?['extras'] as Map<Object?, Object?>?)?['proxyPort'],
      23333,
    );
  });

  test('omits proxy port when Lightly has no active local proxy', () async {
    const channel = MethodChannel('optional_plugin_direct_launch_test');
    Map<Object?, Object?>? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          arguments = (call.arguments as Map).cast<Object?, Object?>();
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final coordinator = OptionalFeatureCoordinator(
      platformGateway: OptionalPluginPlatformGateway(channel: channel),
      localProxyEndpoint: const _FakeLocalProxyEndpoint(null),
    );

    expect(await coordinator.launchTelegramPlugin(), isTrue);
    expect(arguments?['extras'], isEmpty);
  });
}

class _FakeLocalProxyEndpoint implements LocalProxyEndpointProvider {
  const _FakeLocalProxyEndpoint(this.localSocks5Port);

  @override
  final int? localSocks5Port;
}
