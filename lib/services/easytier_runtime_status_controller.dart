import '../features/easytier/domain/easytier_config.dart';
import 'easytier_network_info_analyzer.dart';

class EasyTierStatusLoadResult {
  const EasyTierStatusLoadResult({
    this.networkInfo,
    this.nextIp,
    this.errorMessage,
    required this.shouldRestartServices,
  });

  final Map<String, dynamic>? networkInfo;
  final String? nextIp;
  final String? errorMessage;
  final bool shouldRestartServices;
}

class EasyTierStartResult {
  const EasyTierStartResult({
    required this.isRunning,
    this.statusMessage,
    this.errorMessage,
    required this.shouldLoadStatus,
  });

  final bool isRunning;
  final String? statusMessage;
  final String? errorMessage;
  final bool shouldLoadStatus;
}

class EasyTierStopResult {
  const EasyTierStopResult({
    required this.isRunning,
    this.statusMessage,
    this.errorMessage,
    required this.clearNetworkInfo,
  });

  final bool isRunning;
  final String? statusMessage;
  final String? errorMessage;
  final bool clearNetworkInfo;
}

class EasyTierRuntimeStatusController {
  const EasyTierRuntimeStatusController({
    required Future<bool> Function(EasyTierConfig config) startVpn,
    required Future<bool> Function(EasyTierConfig config) startNoTun,
    required Future<void> Function() stopVpn,
    required Future<Map<String, dynamic>?> Function() getNetworkInfo,
    required String? Function() readLastError,
  }) : _startVpn = startVpn,
       _startNoTun = startNoTun,
       _stopVpn = stopVpn,
       _getNetworkInfo = getNetworkInfo,
       _readLastError = readLastError;

  final Future<bool> Function(EasyTierConfig config) _startVpn;
  final Future<bool> Function(EasyTierConfig config) _startNoTun;
  final Future<void> Function() _stopVpn;
  final Future<Map<String, dynamic>?> Function() _getNetworkInfo;
  final String? Function() _readLastError;

  Future<EasyTierStatusLoadResult> loadStatus({
    required String instanceName,
    required String? previousIp,
  }) async {
    try {
      final info = await _getNetworkInfo();
      final nextIp = EasyTierNetworkInfoAnalyzer.extractInstanceIpv4(
        info,
        instanceName,
      );
      return EasyTierStatusLoadResult(
        networkInfo: info,
        nextIp: nextIp,
        errorMessage: null,
        shouldRestartServices: nextIp != null && nextIp != previousIp,
      );
    } catch (error) {
      return EasyTierStatusLoadResult(
        errorMessage: '读取网络状态失败：$error',
        shouldRestartServices: false,
      );
    }
  }

  Future<EasyTierStartResult> startVpn(
    EasyTierConfig config, {
    required bool useNoTunMode,
  }) async {
    try {
      final success = useNoTunMode
          ? await _startNoTun(config)
          : await _startVpn(config);
      if (success) {
        return EasyTierStartResult(
          isRunning: true,
          statusMessage: useNoTunMode ? '非 VPN 模式启动成功' : 'VPN 启动成功',
          errorMessage: null,
          shouldLoadStatus: true,
        );
      }

      return EasyTierStartResult(
        isRunning: false,
        statusMessage: null,
        errorMessage: _readLastError() ?? '启动失败，请查看导出日志',
        shouldLoadStatus: false,
      );
    } catch (error) {
      return EasyTierStartResult(
        isRunning: false,
        statusMessage: null,
        errorMessage: error.toString(),
        shouldLoadStatus: false,
      );
    }
  }

  Future<EasyTierStopResult> stopVpn() async {
    try {
      await _stopVpn();
      return const EasyTierStopResult(
        isRunning: false,
        statusMessage: 'VPN 已停止',
        errorMessage: null,
        clearNetworkInfo: true,
      );
    } catch (error) {
      return EasyTierStopResult(
        isRunning: true,
        statusMessage: null,
        errorMessage: error.toString(),
        clearNetworkInfo: false,
      );
    }
  }
}
