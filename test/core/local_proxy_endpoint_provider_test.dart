import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lightly/features/proxy/infrastructure/proxy_service_local_endpoint_adapter.dart';
import 'package:lightly/core/network/local_proxy_endpoint_provider.dart';
import 'package:lightly/features/telegram/telegram_tdlib_service.dart';

/// Test double standing in for the proxy implementation.
class _FakeProxyEndpointProvider implements LocalProxyEndpointProvider {
  _FakeProxyEndpointProvider(this._port);

  int? _port;

  @override
  int? get localSocks5Port => _port;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<int?> resolveAvailableLocalSocks5Port() async => _port;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalProxyEndpointProvider port contract', () {
    test('fake reflects the current port and null when absent', () {
      final provider = _FakeProxyEndpointProvider(23333);
      expect(provider.localSocks5Port, 23333);

      provider._port = null;
      expect(provider.localSocks5Port, isNull);
    });

    test('adapter returns null while the proxy is not running', () {
      // A freshly constructed ProxyService is not running, so the adapter must
      // surface null — the exact "direct connection" signal Telegram relies on.
      final adapter = ProxyServiceLocalEndpointAdapter();
      expect(adapter.localSocks5Port, isNull);
    });

    test('adapter accepts a listener when the runtime flag is stale', () async {
      final adapter = ProxyServiceLocalEndpointAdapter(
        listenerProbe: (host, port) async =>
            host == '127.0.0.1' && port == 23333,
      );
      expect(await adapter.resolveAvailableLocalSocks5Port(), 23333);
    });

    test('adapter probes the persisted custom SOCKS5 port', () async {
      final checkedPorts = <int>[];
      final adapter = ProxyServiceLocalEndpointAdapter(
        persistedPortLoader: () async => 24444,
        listenerProbe: (host, port) async {
          checkedPorts.add(port);
          return host == '127.0.0.1' && port == 24444;
        },
      );

      expect(await adapter.resolveAvailableLocalSocks5Port(), 24444);
      expect(checkedPorts.first, 24444);
    });

    test('production probe requires a SOCKS5 method reply', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final greeting = Completer<List<int>>();
      final subscription = server.listen((socket) {
        socket.listen((data) {
          if (!greeting.isCompleted) greeting.complete(data);
          socket.add(const <int>[0x05, 0x00]);
        });
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close();
      });
      final adapter = ProxyServiceLocalEndpointAdapter(
        persistedPortLoader: () async => server.port,
      );

      expect(await adapter.resolveAvailableLocalSocks5Port(), server.port);
      expect(await greeting.future, const <int>[0x05, 0x01, 0x00]);
    });

    test('production probe rejects a non-SOCKS listener', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((socket) {
        socket.listen((_) => socket.add(const <int>[0x4f, 0x4b]));
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close();
      });
      final adapter = ProxyServiceLocalEndpointAdapter(
        persistedPortLoader: () async => server.port,
      );

      expect(await adapter.resolveAvailableLocalSocks5Port(), isNull);
    });
  });

  group('TelegramTdlibService proxy port injection', () {
    test('defaults to a null provider (direct connection) before wiring', () {
      // The singleton must not assume a proxy exists until the composition root
      // injects a provider.
      expect(
        TelegramTdlibService.instance.proxyEndpointProvider.localSocks5Port,
        isNull,
      );
    });

    test('honours an injected provider', () {
      final service = TelegramTdlibService.instance;
      final original = service.proxyEndpointProvider;
      addTearDown(() => service.proxyEndpointProvider = original);

      service.proxyEndpointProvider = _FakeProxyEndpointProvider(18081);
      expect(service.proxyEndpointProvider.localSocks5Port, 18081);
    });
  });
}
