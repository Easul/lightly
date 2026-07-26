class EasyTierLocalHttpExposureResult {
  const EasyTierLocalHttpExposureResult({
    required this.bindAllInterfaces,
    required this.message,
  });

  final bool bindAllInterfaces;
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
    required this.restartLocalHttp,
    required this.restartClipboard,
    required this.preferredClipboardPort,
  });

  final bool restartLocalHttp;
  final bool restartClipboard;
  final int preferredClipboardPort;
}

class EasyTierServiceAccessCoordinator {
  const EasyTierServiceAccessCoordinator();

  EasyTierLocalHttpExposureResult? enableLocalHttpVpnExposure({
    required bool canConfigureLocalHttp,
  }) {
    if (!canConfigureLocalHttp) {
      return null;
    }

    return const EasyTierLocalHttpExposureResult(
      bindAllInterfaces: true,
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
    required bool localHttpEnabled,
    required bool clipboardRunning,
    required int? configuredClipboardPort,
    required int? boundClipboardPort,
  }) {
    final preferredClipboardPort =
        configuredClipboardPort ?? boundClipboardPort ?? 12345;
    final restartClipboard =
        clipboardRunning || preferredClipboardPort == 12345;
    return EasyTierServiceRestartPlan(
      restartLocalHttp: localHttpEnabled,
      restartClipboard: restartClipboard,
      preferredClipboardPort: preferredClipboardPort,
    );
  }
}
