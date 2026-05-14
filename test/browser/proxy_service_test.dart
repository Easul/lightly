import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/local_mixed_proxy_server.dart';
import 'package:lightly/browser/proxy_service.dart';
import 'package:lightly/browser/vless_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProxyService', () {
    const channel = MethodChannel('browser_proxy');
    final methodCalls = <MethodCall>[];

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methodCalls.add(call);
            return null;
          });
      methodCalls.clear();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('passes tls security to VlessConfig for non-443 ws nodes', () async {
      final fakeServer = _FakeLocalMixedProxyServer();
      final service = ProxyService(
        localProxyServer: fakeServer,
        proxyChannel: channel,
      );

      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyScheme: BrowserProxyProtocol.vless,
        proxyHost: 'api.example.com',
        proxyPort: 2083,
        localProxyPort: 19090,
        proxyUuid: '86c50e3a-5b87-49dd-bd20-03c7f2735e40',
        proxyTlsEnabled: true,
        proxyServerName: 'vc.example.com',
        proxyTransportType: 'ws',
        proxyTransportPath: '/speedtest',
        proxyTransportHost: 'vc.example.com',
      );

      await service.applyProxy(settings);

      expect(fakeServer.lastConfig, isNotNull);
      expect(fakeServer.lastConfig!.security, 'tls');
      expect(fakeServer.lastConfig!.isTlsEnabled, isTrue);
      expect(fakeServer.lastConfig!.transportType, 'ws');
      expect(fakeServer.lastConfig!.wsHost, 'vc.example.com');
      expect(fakeServer.lastConfig!.wsPath, '/speedtest');
      expect(fakeServer.lastConfig!.sni, 'vc.example.com');
      expect(fakeServer.lastPreferredPort, 19090);
    });

    test('passes none security when vless tls is disabled', () async {
      final fakeServer = _FakeLocalMixedProxyServer();
      final service = ProxyService(
        localProxyServer: fakeServer,
        proxyChannel: channel,
      );

      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyScheme: BrowserProxyProtocol.vless,
        proxyHost: 'example.com',
        proxyPort: 80,
        proxyUuid: '86c50e3a-5b87-49dd-bd20-03c7f2735e40',
        proxyTlsEnabled: false,
        proxyTransportType: 'ws',
        proxyTransportPath: '/',
        proxyTransportHost: 'edge.example.com',
      );

      await service.applyProxy(settings);

      expect(fakeServer.lastConfig, isNotNull);
      expect(fakeServer.lastConfig!.security, 'none');
      expect(fakeServer.lastConfig!.isTlsEnabled, isFalse);
    });

    test('does not restart unchanged vless proxy config', () async {
      final fakeServer = _FakeLocalMixedProxyServer();
      final service = ProxyService(
        localProxyServer: fakeServer,
        proxyChannel: channel,
      );

      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyScheme: BrowserProxyProtocol.vless,
        proxyHost: 'example.com',
        proxyPort: 443,
        proxyUuid: '86c50e3a-5b87-49dd-bd20-03c7f2735e40',
        proxyTlsEnabled: true,
        proxyServerName: 'example.com',
        proxyTransportType: 'ws',
        proxyTransportPath: '/',
      );

      await service.applyProxy(settings);
      final firstStartCount = fakeServer.startCount;

      await service.applyProxy(settings);

      expect(fakeServer.startCount, firstStartCount);
      expect(fakeServer.stopCount, 0);
    });

    test('reapplies unchanged vless proxy config to webview proxy', () async {
      final fakeServer = _FakeLocalMixedProxyServer();
      final service = ProxyService(
        localProxyServer: fakeServer,
        proxyChannel: channel,
      );

      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyScheme: BrowserProxyProtocol.vless,
        proxyHost: 'example.com',
        proxyPort: 443,
        proxyUuid: '86c50e3a-5b87-49dd-bd20-03c7f2735e40',
        proxyTlsEnabled: true,
      );

      await service.applyProxy(settings);
      await service.applyProxy(settings);

      final setProxyCalls = methodCalls.where(
        (call) => call.method == 'setProxy',
      );
      expect(setProxyCalls.length, 2);
      expect(fakeServer.startCount, 1);
    });

    test('passes packetEncoding to VlessConfig', () async {
      final fakeServer = _FakeLocalMixedProxyServer();
      final service = ProxyService(
        localProxyServer: fakeServer,
        proxyChannel: channel,
      );

      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyScheme: BrowserProxyProtocol.vless,
        proxyHost: 'api.example.com',
        proxyPort: 2095,
        proxyUuid: '86c50e3a-5b87-49dd-bd20-03c7f2735e40',
        proxyTransportType: 'ws',
        proxyTransportPath: '/',
        proxyTransportHost: 'edge.example.com',
        proxyPacketEncoding: 'xudp',
      );

      await service.applyProxy(settings);

      expect(fakeServer.lastConfig, isNotNull);
      expect(fakeServer.lastConfig!.packetEncoding, 'xudp');
    });

    test(
      'describeError hints insecure certificate on TLS handshake failure',
      () {
        final service = ProxyService(proxyChannel: channel);

        final message = service.describeError(
          const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
        );

        expect(message, contains('允许不安全证书'));
        expect(message, contains('SNI'));
      },
    );
  });
}

class _FakeLocalMixedProxyServer extends LocalMixedProxyServer {
  VlessConfig? lastConfig;
  int? lastPreferredPort;
  bool _running = false;
  int startCount = 0;
  int stopCount = 0;

  @override
  bool get isRunning => _running;

  @override
  int? get boundPort => 18080;

  @override
  Future<void> start(VlessConfig config, {int? preferredPort}) async {
    lastConfig = config;
    lastPreferredPort = preferredPort;
    _running = true;
    startCount += 1;
  }

  @override
  Future<void> stop() async {
    _running = false;
    stopCount += 1;
  }
}
