import 'easytier_config.dart';

abstract class EasyTierRuntime {
  bool get isRunning;

  bool get isNoTunMode;

  int? get activeNoTunSocksPort;

  String? get currentInstanceName;

  Future<Map<String, dynamic>?> getNetworkInfo();

  Future<bool> startVpn(EasyTierConfig config);

  Future<bool> startNoTun(EasyTierConfig config);

  Future<void> stopVpn();
}
