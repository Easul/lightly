import '../browser/browser_settings.dart';

class EasyTierLocalHttpExposureResult {
  const EasyTierLocalHttpExposureResult({
    required this.settings,
    required this.message,
  });

  final BrowserSettings settings;
  final String message;
}

class EasyTierClipboardStartResult {
  const EasyTierClipboardStartResult({
    required this.didChange,
    required this.message,
  });

  final bool didChange;
  final String? message;
}

class EasyTierServiceRestartPlan {
  const EasyTierServiceRestartPlan({
    this.localHttpSettings,
    required this.restartClipboard,
    required this.preferredClipboardPort,
  });

  final BrowserSettings? localHttpSettings;
  final bool restartClipboard;
  final int preferredClipboardPort;
}

class EasyTierServiceAccessCoordinator {
  const EasyTierServiceAccessCoordinator();

  EasyTierLocalHttpExposureResult? enableLocalHttpVpnExposure(
    BrowserSettings? settings,
  ) {
    if (settings == null) {
      return null;
    }

    final updated = settings.copyWith(localHttpBindAllInterfaces: true);
    return EasyTierLocalHttpExposureResult(
      settings: updated,
      message: '3001 服务已切换为 VPN 可访问模式',
    );
  }

  EasyTierClipboardStartResult startClipboardServiceIfNeeded({
    required bool isRunning,
  }) {
    if (isRunning) {
      return const EasyTierClipboardStartResult(
        didChange: false,
        message: null,
      );
    }
    return const EasyTierClipboardStartResult(
      didChange: true,
      message: '12345 剪贴板服务已启动',
    );
  }

  EasyTierServiceRestartPlan buildRestartPlan({
    required BrowserSettings? browserSettings,
    required bool clipboardRunning,
    required int? configuredClipboardPort,
    required int? boundClipboardPort,
  }) {
    final localHttpSettings =
        browserSettings != null && browserSettings.localHttpServerEnabled
        ? browserSettings
        : null;
    final preferredClipboardPort =
        configuredClipboardPort ?? boundClipboardPort ?? 12345;
    final restartClipboard =
        clipboardRunning || preferredClipboardPort == 12345;
    return EasyTierServiceRestartPlan(
      localHttpSettings: localHttpSettings,
      restartClipboard: restartClipboard,
      preferredClipboardPort: preferredClipboardPort,
    );
  }
}
