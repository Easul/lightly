import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/app/remote_control_page_coordinator.dart';
import 'package:lightly/features/easytier/domain/easytier_config.dart';
import 'package:lightly/features/easytier/domain/easytier_runtime.dart';
import 'package:lightly/features/proxy/domain/proxy_configuration.dart';
import 'package:lightly/features/proxy/domain/proxy_protocol.dart';
import 'package:lightly/features/proxy/domain/proxy_runtime.dart';

void main() {
  test(
    'initializes proxy state and starts configured proxy on demand',
    () async {
      final proxy = _FakeProxyRuntime();
      final coordinator = RemoteControlPageCoordinator(
        easyTier: _FakeEasyTierRuntime(),
        proxy: proxy,
        loadProxyConfiguration: () async => _proxyConfiguration(),
        ensureEasyTier: ({bool noTunMode = false}) async => true,
        shutdownAll: () async {},
      );

      final state = await coordinator.initialize();
      final port = await coordinator.ensureInternalProxyReady(
        useInternalProxy: true,
      );

      expect(state.isProxyRunning, isFalse);
      expect(proxy.applyCalls, 1);
      expect(port, 23333);
    },
  );

  test('rejects internal proxy when no enabled configuration exists', () async {
    final coordinator = RemoteControlPageCoordinator(
      easyTier: _FakeEasyTierRuntime(),
      proxy: _FakeProxyRuntime(),
      loadProxyConfiguration: () async => null,
      ensureEasyTier: ({bool noTunMode = false}) async => true,
      shutdownAll: () async {},
    );
    await coordinator.initialize();

    expect(
      () => coordinator.ensureInternalProxyReady(useInternalProxy: true),
      throwsA(
        isA<RemoteControlPageRuntimeException>().having(
          (error) => error.message,
          'message',
          '请先在设置中配置并启用代理',
        ),
      ),
    );
  });

  test('returns only reachable EasyTier peers', () async {
    final easyTier = _FakeEasyTierRuntime(
      isRunning: true,
      networkInfo: _networkInfo,
    );
    final coordinator = RemoteControlPageCoordinator(
      easyTier: easyTier,
      proxy: _FakeProxyRuntime(),
      loadProxyConfiguration: () async => null,
      ensureEasyTier: ({bool noTunMode = false}) async => true,
      shutdownAll: () async {},
    );

    final peers = await coordinator.loadReachablePeers();

    expect(peers, hasLength(1));
    expect(peers!.single['name'], 'peer-a');
    expect(coordinator.isEasyTierNoTunMode, isFalse);
  });

  test('delegates receiver network startup and full shutdown', () async {
    var requestedNoTun = false;
    var shutdownCalls = 0;
    final coordinator = RemoteControlPageCoordinator(
      easyTier: _FakeEasyTierRuntime(),
      proxy: _FakeProxyRuntime(),
      loadProxyConfiguration: () async => null,
      ensureEasyTier: ({bool noTunMode = false}) async {
        requestedNoTun = noTunMode;
        return true;
      },
      shutdownAll: () async {
        shutdownCalls++;
      },
    );

    expect(await coordinator.ensureReceiverNetwork(noTunMode: true), isTrue);
    await coordinator.shutdownAll();

    expect(requestedNoTun, isTrue);
    expect(shutdownCalls, 1);
  });
}

ProxyConfiguration _proxyConfiguration() {
  return const ProxyConfiguration(
    proxyEnabled: true,
    proxyHost: 'proxy.example.com',
    proxyPort: 443,
    proxyProtocol: BrowserProxyProtocol.vless,
    proxyUuid: 'uuid',
    proxyTlsEnabled: true,
    proxyTlsInsecure: false,
    proxyServerName: '',
    proxyTransportType: 'ws',
    proxyTransportPath: '/',
    proxyTransportHost: '',
    proxyPacketEncoding: '',
    proxyBypassDomainList: <String>[],
    localProxyPort: 23333,
  );
}

class _FakeProxyRuntime implements ProxyRuntime {
  bool running = false;
  int applyCalls = 0;

  @override
  bool get isRunning => running;

  @override
  int? get localProxyPort => 23333;

  @override
  Stream<bool> get runningStream => const Stream<bool>.empty();

  @override
  Future<void> applyProxy(ProxyConfiguration configuration) async {
    applyCalls++;
    running = true;
  }
}

class _FakeEasyTierRuntime implements EasyTierRuntime {
  _FakeEasyTierRuntime({this.isRunning = false, this.networkInfo});

  @override
  bool isRunning;

  @override
  bool get isNoTunMode => false;

  @override
  int? get activeNoTunSocksPort => null;

  @override
  String? get currentInstanceName => 'demo';

  final Map<String, dynamic>? networkInfo;

  @override
  Future<Map<String, dynamic>?> getNetworkInfo() async => networkInfo;

  @override
  Future<bool> startNoTun(EasyTierConfig config) async => true;

  @override
  Future<bool> startVpn(EasyTierConfig config) async => true;

  @override
  Future<void> stopVpn() async {}
}

final Map<String, dynamic> _networkInfo = <String, dynamic>{
  'map': <String, dynamic>{
    'demo': <String, dynamic>{
      'routes': <dynamic>[
        <String, dynamic>{
          'peer_id': 1,
          'hostname': 'peer-a',
          'cost': 1,
          'next_hop_peer_id': 1,
          'path_latency': 12,
          'ipv4_addr': <String, dynamic>{
            'address': <String, dynamic>{'addr': 0x0A7E7E17},
            'network_length': 24,
          },
        },
      ],
      'peers': <dynamic>[
        <String, dynamic>{
          'peer_id': 1,
          'directly_connected_conns': <dynamic>['x'],
        },
        <String, dynamic>{
          'peer_id': 2,
          'hostname': 'offline-peer',
          'directly_connected_conns': <dynamic>[],
        },
      ],
      'events': <dynamic>[],
    },
  },
};
