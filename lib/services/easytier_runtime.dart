import '../features/easytier/domain/easytier_config.dart';

abstract class EasyTierRuntime {
  bool get isRunning;

  bool get isNoTunMode;

  Future<bool> startVpn(EasyTierConfig config);

  Future<bool> startNoTun(EasyTierConfig config);

  Future<void> stopVpn();
}
