import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/services/browser_settings_runtime_service.dart';

void main() {
  group('BrowserSettingsRuntimeService', () {
    late BrowserSettingsRuntimeService runtimeService;
    BrowserSettings? savedSettings;
    BrowserSettings? appliedProxySettings;
    BrowserSettings? appliedLocalHttpSettings;
    var proxyCleared = false;
    var localHttpStopped = false;

    setUp(() {
      savedSettings = null;
      appliedProxySettings = null;
      appliedLocalHttpSettings = null;
      proxyCleared = false;
      localHttpStopped = false;
      runtimeService = BrowserSettingsRuntimeService(
        saveSettings: (settings) async {
          savedSettings = settings;
        },
        applyProxy: (settings) async {
          appliedProxySettings = settings;
        },
        clearProxy: () async {
          proxyCleared = true;
        },
        applyLocalHttpSettings: (settings) async {
          appliedLocalHttpSettings = settings;
        },
        stopLocalHttpServer: () async {
          localHttpStopped = true;
        },
      );
    });

    test(
      'saveSettings applies proxy when configuration changed and enabled',
      () async {
        final previous = BrowserSettings.defaults().copyWith(
          proxyEnabled: false,
          localHttpServerEnabled: true,
        );
        final next = previous.copyWith(
          proxyEnabled: true,
          proxyHost: '1.2.3.4',
          proxyPort: 8080,
        );

        final result = await runtimeService.saveSettings(
          settings: next,
          previousSettings: previous,
        );

        expect(savedSettings, next);
        expect(appliedProxySettings, next);
        expect(appliedLocalHttpSettings, next);
        expect(result.appliedChanges, isTrue);
        expect(result.message, contains('代理已保存并应用'));
      },
    );

    test('saveSettings stops local http service when disabled', () async {
      final settings = BrowserSettings.defaults().copyWith(
        proxyEnabled: false,
        localHttpServerEnabled: false,
      );

      final result = await runtimeService.saveSettings(
        settings: settings,
        previousSettings: settings,
      );

      expect(appliedProxySettings, isNull);
      expect(proxyCleared, isFalse);
      expect(localHttpStopped, isTrue);
      expect(result.message, '设置已保存');
    });

    test(
      'enableProxy and disableProxy persist settings and switch proxy state',
      () async {
        final settings = BrowserSettings.defaults().copyWith(
          proxyEnabled: true,
          proxyHost: '1.2.3.4',
          proxyPort: 8080,
        );

        final enableResult = await runtimeService.enableProxy(settings);
        final disableResult = await runtimeService.disableProxy(
          settings.copyWith(proxyEnabled: false),
        );

        expect(enableResult.message, contains('代理已启动'));
        expect(disableResult.message, '代理已停止');
        expect(appliedProxySettings, settings);
        expect(proxyCleared, isTrue);
      },
    );
  });
}
