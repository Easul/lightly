import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/local_sharing/local_http/local_http_file_server_service.dart';
import 'package:lightly/features/proxy/infrastructure/proxy_service.dart';
import 'package:lightly/browser/services/browser_proxy_status_monitor.dart';

void main() {
  group('BrowserProxyStatusMonitor', () {
    late BrowserProxyStatusMonitor monitor;

    setUp(() {
      monitor = BrowserProxyStatusMonitor(
        proxyService: ProxyService(),
        localHttpFileServerService: LocalHttpFileServerService(),
      );
    });

    tearDown(() {
      monitor.dispose();
    });

    test('starts from current proxy and local-http snapshots', () {
      expect(monitor.proxyState.value, ProxyService().currentState);
      expect(monitor.localHttpState.value, LocalHttpFileServerState.stopped);
    });

    test('allows explicit optimistic state updates', () {
      monitor.setProxyState(ProxyState.starting);
      monitor.setLocalHttpState(LocalHttpFileServerState.starting);

      expect(monitor.proxyState.value, ProxyState.starting);
      expect(monitor.localHttpState.value, LocalHttpFileServerState.starting);
    });
  });
}
