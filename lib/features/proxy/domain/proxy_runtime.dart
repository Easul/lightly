import 'proxy_configuration.dart';

abstract class ProxyRuntime {
  bool get isRunning;

  int? get localProxyPort;

  Stream<bool> get runningStream;

  Future<void> applyProxy(ProxyConfiguration configuration);
}
