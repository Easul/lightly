import 'package:flutter_test/flutter_test.dart';

import 'package:lightly/browser/services/proxy_service_local_endpoint_adapter.dart';
import 'package:lightly/core/network/local_proxy_endpoint_provider.dart';
import 'package:lightly/telegram_checkin/telegram_tdlib_service.dart';

/// Test double standing in for the proxy implementation.
class _FakeProxyEndpointProvider implements LocalProxyEndpointProvider {
  _FakeProxyEndpointProvider(this._port);

  int? _port;

  @override
  int? get localSocks5Port => _port;
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
