import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/proxy_service.dart';
import 'package:lightly/features/proxy/infrastructure/proxy_core_service.dart'
    as proxy_core;

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
      final fakeProxyCore = _FakeProxyCoreService();
      final service = ProxyService(
        proxyCoreService: fakeProxyCore,
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

      expect(fakeProxyCore.lastConfig, isNotNull);
      expect(fakeProxyCore.lastConfig!.security, 'tls');
      expect(fakeProxyCore.lastConfig!.serverAddr, 'api.example.com');
      expect(fakeProxyCore.lastConfig!.serverPort, 2083);
      expect(fakeProxyCore.lastConfig!.host, 'vc.example.com');
      expect(fakeProxyCore.lastConfig!.path, '/speedtest');
      expect(fakeProxyCore.lastConfig!.sni, 'vc.example.com');
      expect(fakeProxyCore.lastListenAddr, '127.0.0.1:19090');
    });

    test('passes none security when vless tls is disabled', () async {
      final fakeProxyCore = _FakeProxyCoreService();
      final service = ProxyService(
        proxyCoreService: fakeProxyCore,
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

      expect(fakeProxyCore.lastConfig, isNotNull);
      expect(fakeProxyCore.lastConfig!.security, 'none');
      expect(fakeProxyCore.lastConfig!.serverPort, 80);
    });

    test('does not restart unchanged vless proxy config', () async {
      final fakeProxyCore = _FakeProxyCoreService();
      final service = ProxyService(
        proxyCoreService: fakeProxyCore,
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
      final firstStartCount = fakeProxyCore.startCount;

      await service.applyProxy(settings);

      expect(fakeProxyCore.startCount, firstStartCount);
      expect(fakeProxyCore.stopCount, 0);
    });

    test('reapplies unchanged vless proxy config to webview proxy', () async {
      final fakeProxyCore = _FakeProxyCoreService();
      final service = ProxyService(
        proxyCoreService: fakeProxyCore,
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
      expect(fakeProxyCore.startCount, 1);
    });

    test(
      'reapplies unchanged http proxy config without starting proxy core',
      () async {
        final fakeProxyCore = _FakeProxyCoreService();
        final service = ProxyService(
          proxyCoreService: fakeProxyCore,
          proxyChannel: channel,
        );

        final settings = BrowserSettings.defaults().copyWith(
          proxyEnabled: true,
          proxyScheme: BrowserProxyProtocol.http,
          proxyHost: 'proxy.example.com',
          proxyPort: 8080,
        );

        await service.applyProxy(settings);
        await service.applyProxy(settings);

        final setProxyCalls = methodCalls.where(
          (call) => call.method == 'setProxy',
        );
        expect(setProxyCalls.length, 2);
        expect(fakeProxyCore.startCount, 0);
        expect(fakeProxyCore.stopCount, 0);
      },
    );

    test('passes transport host/path to rust VlessConfig', () async {
      final fakeProxyCore = _FakeProxyCoreService();
      final service = ProxyService(
        proxyCoreService: fakeProxyCore,
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

      expect(fakeProxyCore.lastConfig, isNotNull);
      expect(fakeProxyCore.lastConfig!.host, 'edge.example.com');
      expect(fakeProxyCore.lastConfig!.path, '/');
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

    test('passes Hysteria2 config to rust proxy core', () async {
      final fakeProxyCore = _FakeProxyCoreService();
      final service = ProxyService(
        proxyCoreService: fakeProxyCore,
        proxyChannel: channel,
      );

      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyScheme: BrowserProxyProtocol.hysteria2,
        proxyHost: 'hy2.example.com',
        proxyPort: 443,
        proxyUuid: 'secret-password',
        proxyServerName: 'sni.example.com',
        proxyTransportType: 'salamander',
        proxyTransportHost: 'obfs-secret',
        proxyTlsInsecure: true,
        localProxyPort: 19091,
      );

      await service.applyProxy(settings);

      expect(fakeProxyCore.lastHysteria2Config, isNotNull);
      expect(fakeProxyCore.lastHysteria2Config!.serverAddr, 'hy2.example.com');
      expect(fakeProxyCore.lastHysteria2Config!.serverPort, 443);
      expect(fakeProxyCore.lastHysteria2Config!.password, 'secret-password');
      expect(fakeProxyCore.lastHysteria2Config!.sni, 'sni.example.com');
      expect(fakeProxyCore.lastHysteria2Config!.obfs, 'salamander');
      expect(fakeProxyCore.lastHysteria2Config!.obfsPassword, 'obfs-secret');
      expect(fakeProxyCore.lastHysteria2Config!.tlsInsecure, isTrue);
      expect(fakeProxyCore.lastListenAddr, '127.0.0.1:19091');
    });

    test('findProxyForDownload returns DIRECT when proxy is disabled', () {
      final service = ProxyService(proxyChannel: channel);
      final settings = BrowserSettings.defaults().copyWith(proxyEnabled: false);

      final result = service.findProxyForDownload(
        settings,
        Uri.parse('https://example.com/file.apk'),
      );

      expect(result, 'DIRECT');
    });

    test('findProxyForDownload returns DIRECT for bypassed domains', () {
      final service = ProxyService(proxyChannel: channel);
      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: true,
        proxyScheme: BrowserProxyProtocol.http,
        proxyHost: 'proxy.example.com',
        proxyPort: 8080,
      );

      final result = service.findProxyForDownload(
        settings,
        Uri.parse('https://accounts.google.com/o/oauth2/v2/auth'),
      );

      expect(result, 'DIRECT');
    });

    test(
      'findProxyForDownload returns upstream HTTP proxy when configured',
      () {
        final service = ProxyService(proxyChannel: channel);
        final settings = BrowserSettings.defaults().copyWith(
          proxyEnabled: true,
          proxyScheme: BrowserProxyProtocol.http,
          proxyHost: 'proxy.example.com',
          proxyPort: 8080,
        );

        final result = service.findProxyForDownload(
          settings,
          Uri.parse('https://example.com/file.apk'),
        );

        expect(result, 'PROXY proxy.example.com:8080');
      },
    );

    test(
      'findProxyForDownload returns local loopback proxy for vless',
      () async {
        final fakeProxyCore = _FakeProxyCoreService();
        final service = ProxyService(
          proxyCoreService: fakeProxyCore,
          proxyChannel: channel,
        );
        final settings = BrowserSettings.defaults().copyWith(
          proxyEnabled: true,
          proxyScheme: BrowserProxyProtocol.vless,
          proxyHost: 'edge.example.com',
          proxyPort: 443,
          proxyUuid: '86c50e3a-5b87-49dd-bd20-03c7f2735e40',
          proxyTlsEnabled: true,
          localProxyPort: 19090,
        );

        await service.applyProxy(settings);

        final result = service.findProxyForDownload(
          settings,
          Uri.parse('https://example.com/file.apk'),
        );

        expect(result, 'PROXY 127.0.0.1:19090');
      },
    );
  });
}

class _FakeProxyCoreService extends proxy_core.ProxyCoreService {
  proxy_core.VlessConfig? lastConfig;
  proxy_core.Hysteria2Config? lastHysteria2Config;
  String? lastListenAddr;
  bool _running = false;
  int startCount = 0;
  int stopCount = 0;

  @override
  bool get isRunning => _running;

  @override
  String get listenAddr => lastListenAddr ?? '127.0.0.1:18080';

  @override
  Future<int> init({String logLevel = 'info'}) async {
    return 0;
  }

  @override
  Future<int> start({
    String listenAddr = '127.0.0.1:23333',
    proxy_core.VlessConfig? vlessConfig,
    proxy_core.Hysteria2Config? hysteria2Config,
  }) async {
    lastConfig = vlessConfig;
    lastHysteria2Config = hysteria2Config;
    lastListenAddr = listenAddr;
    _running = true;
    startCount += 1;
    return 0;
  }

  @override
  Future<int> startWithHysteria2({
    String logLevel = 'info',
    String listenAddr = '127.0.0.1:23333',
    required proxy_core.Hysteria2Config hysteria2Config,
  }) async {
    lastHysteria2Config = hysteria2Config;
    lastListenAddr = listenAddr;
    _running = true;
    startCount += 1;
    return 0;
  }

  @override
  Future<int> startWithVless({
    String logLevel = 'info',
    String listenAddr = '127.0.0.1:23333',
    required proxy_core.VlessConfig vlessConfig,
  }) async {
    lastConfig = vlessConfig;
    lastListenAddr = listenAddr;
    _running = true;
    startCount += 1;
    return 0;
  }

  @override
  Future<int> stop() async {
    _running = false;
    stopCount += 1;
    return 0;
  }
}
