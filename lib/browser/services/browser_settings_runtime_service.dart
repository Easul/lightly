import '../browser_settings.dart';

class BrowserSettingsSaveResult {
  const BrowserSettingsSaveResult({
    required this.message,
    required this.appliedChanges,
  });

  final String message;
  final bool appliedChanges;
}

class BrowserSettingsRuntimeService {
  BrowserSettingsRuntimeService({
    required Future<void> Function(BrowserSettings settings) saveSettings,
    required Future<void> Function(BrowserSettings settings) applyProxy,
    required Future<void> Function() clearProxy,
    required Future<void> Function(BrowserSettings settings)
    applyLocalHttpSettings,
    required Future<void> Function() stopLocalHttpServer,
  }) : _saveSettings = saveSettings,
       _applyProxy = applyProxy,
       _clearProxy = clearProxy,
       _applyLocalHttpSettings = applyLocalHttpSettings,
       _stopLocalHttpServer = stopLocalHttpServer;

  final Future<void> Function(BrowserSettings settings) _saveSettings;
  final Future<void> Function(BrowserSettings settings) _applyProxy;
  final Future<void> Function() _clearProxy;
  final Future<void> Function(BrowserSettings settings) _applyLocalHttpSettings;
  final Future<void> Function() _stopLocalHttpServer;

  Future<BrowserSettingsSaveResult> saveSettings({
    required BrowserSettings settings,
    required BrowserSettings previousSettings,
  }) async {
    await _saveSettings(settings);

    final proxyChanged = !settings.hasSameProxyConfiguration(previousSettings);
    String message;
    if (proxyChanged && settings.proxyEnabled) {
      await _applyProxy(settings);
      message =
          '${BrowserProxyProtocol.label(settings.proxyProtocol)} 代理已保存并应用';
    } else if (proxyChanged) {
      await _clearProxy();
      message = '代理已关闭';
    } else {
      message = '设置已保存';
    }

    if (settings.localHttpServerEnabled) {
      await _applyLocalHttpSettings(settings);
    } else {
      await _stopLocalHttpServer();
    }

    return BrowserSettingsSaveResult(message: message, appliedChanges: true);
  }

  Future<BrowserSettingsSaveResult> enableProxy(
    BrowserSettings settings,
  ) async {
    await _saveSettings(settings);
    await _applyProxy(settings);
    return BrowserSettingsSaveResult(
      message: '${BrowserProxyProtocol.label(settings.proxyProtocol)} 代理已启动',
      appliedChanges: true,
    );
  }

  Future<BrowserSettingsSaveResult> disableProxy(
    BrowserSettings settings,
  ) async {
    await _saveSettings(settings);
    await _clearProxy();
    return const BrowserSettingsSaveResult(
      message: '代理已停止',
      appliedChanges: true,
    );
  }
}
