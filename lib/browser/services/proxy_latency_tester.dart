import '../../features/proxy/domain/proxy_configuration.dart';
import '../../features/proxy/domain/proxy_protocol.dart';
import '../../features/proxy/infrastructure/proxy_core_service.dart'
    as proxy_core;
import '../../features/proxy/infrastructure/proxy_latency_probe.dart';
import 'proxy_runtime_launcher.dart';

class ProxyLatencyTestOperation {
  ProxyLatencyTestOperation({
    required this.result,
    required void Function() onCancel,
  }) : _onCancel = onCancel;

  final Future<Duration?> result;
  final void Function() _onCancel;
  bool _canceled = false;

  void cancel() {
    if (_canceled) {
      return;
    }
    _canceled = true;
    _onCancel();
  }
}

class ProxyLatencyTester {
  const ProxyLatencyTester({
    required this.latencyProbe,
    required this.runtimeLauncher,
    this.localProxyHost = '127.0.0.1',
  });

  final ProxyLatencyProbe latencyProbe;
  final ProxyRuntimeLauncher runtimeLauncher;
  final String localProxyHost;

  ProxyLatencyTestOperation startNodeLatencyTest({
    required ProxyConfiguration settings,
    required proxy_core.ProxyCoreService proxyCoreService,
    required int? currentLocalProxyPort,
    Duration timeout = const Duration(seconds: 10),
    String testUrl = 'https://www.gstatic.com/generate_204',
  }) {
    final cancellationToken = ProxyLatencyCancellationToken();
    return ProxyLatencyTestOperation(
      result: testNodeLatency(
        settings: settings,
        proxyCoreService: proxyCoreService,
        currentLocalProxyPort: currentLocalProxyPort,
        timeout: timeout,
        testUrl: testUrl,
        cancellationToken: cancellationToken,
      ),
      onCancel: cancellationToken.cancel,
    );
  }

  Future<Duration?> testNodeLatency({
    required ProxyConfiguration settings,
    required proxy_core.ProxyCoreService proxyCoreService,
    required int? currentLocalProxyPort,
    Duration timeout = const Duration(seconds: 10),
    String testUrl = 'https://www.gstatic.com/generate_204',
    ProxyLatencyCancellationToken? cancellationToken,
  }) async {
    final testUri = Uri.parse(testUrl);
    final testUrls = [
      testUrl,
      'https://www.google.com/generate_204',
      'https://example.com/',
    ];
    cancellationToken?.throwIfCanceled();

    if (!settings.shouldApplyProxy) {
      final httpLatency = await latencyProbe.measureHttpRequest(
        proxy: null,
        timeout: timeout,
        testUrls: testUrls,
        cancellationToken: cancellationToken,
      );
      if (httpLatency != null) {
        return httpLatency;
      }
      cancellationToken?.throwIfCanceled();
      return latencyProbe.measureTcpConnect(
        host: testUri.host,
        port: testUri.port == 0 ? 443 : testUri.port,
        timeout: timeout,
        cancellationToken: cancellationToken,
      );
    }

    if (settings.proxyProtocol == BrowserProxyProtocol.http) {
      final httpLatency = await latencyProbe.measureHttpRequest(
        proxy: 'PROXY ${settings.proxyHost.trim()}:${settings.proxyPort!}',
        timeout: timeout,
        testUrls: testUrls,
        cancellationToken: cancellationToken,
      );
      if (httpLatency != null) {
        return httpLatency;
      }
      cancellationToken?.throwIfCanceled();
      return latencyProbe.measureTcpConnect(
        host: settings.proxyHost.trim(),
        port: settings.proxyPort!,
        timeout: timeout,
        cancellationToken: cancellationToken,
      );
    }

    if (!runtimeLauncher.supportsRustProxy(settings.proxyProtocol)) {
      throw StateError('Unsupported proxy protocol: ${settings.proxyProtocol}');
    }

    final probeTimeout = timeout < const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : timeout;
    final usingExistingRustProxy = proxyCoreService.isRunning;
    final tempProxyCoreService = usingExistingRustProxy
        ? null
        : proxy_core.ProxyCoreService();
    final tempListenPort = usingExistingRustProxy
        ? currentLocalProxyPort
        : await latencyProbe.allocateEphemeralLoopbackPort();

    if (tempListenPort == null) {
      throw StateError('Temporary Rust proxy port was not assigned');
    }

    try {
      if (tempProxyCoreService != null) {
        cancellationToken?.throwIfCanceled();
        final listenAddr = '$localProxyHost:$tempListenPort';
        final startResult = await runtimeLauncher.startProxyCore(
          proxyCoreService: tempProxyCoreService,
          settings: settings,
          listenAddr: listenAddr,
        );
        if (startResult != 0) {
          throw StateError('Temporary Rust proxy start failed: $startResult');
        }
      }

      final httpLatency = await latencyProbe.measureHttpRequest(
        proxy: 'PROXY $localProxyHost:$tempListenPort',
        timeout: probeTimeout,
        testUrls: testUrls,
        cancellationToken: cancellationToken,
      );
      if (httpLatency != null) {
        return httpLatency;
      }
      cancellationToken?.throwIfCanceled();
      return latencyProbe.measureTcpConnect(
        host: settings.proxyHost.trim(),
        port: settings.proxyPort!,
        timeout: probeTimeout,
        cancellationToken: cancellationToken,
      );
    } finally {
      await tempProxyCoreService?.stop();
    }
  }
}
