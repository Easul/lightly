import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/services/easytier_service_access_coordinator.dart';

void main() {
  group('EasyTierServiceAccessCoordinator', () {
    const coordinator = EasyTierServiceAccessCoordinator();

    test('enableLocalHttpVpnExposure returns updated settings', () {
      final settings = BrowserSettings.defaults().copyWith(
        localHttpServerEnabled: true,
        localHttpBindAllInterfaces: false,
      );
      final result = coordinator.enableLocalHttpVpnExposure(settings);

      expect(result, isNotNull);
      expect(result!.settings.localHttpBindAllInterfaces, isTrue);
      expect(result.message, contains('3001'));
    });

    test('startClipboardServiceIfNeeded only changes when stopped', () {
      expect(
        coordinator.startClipboardServiceIfNeeded(isRunning: true).didChange,
        isFalse,
      );
      expect(
        coordinator.startClipboardServiceIfNeeded(isRunning: false).didChange,
        isTrue,
      );
    });

    test('buildRestartPlan keeps local http only when enabled', () {
      final settings = BrowserSettings.defaults().copyWith(
        localHttpServerEnabled: true,
      );
      final plan = coordinator.buildRestartPlan(
        browserSettings: settings,
        clipboardRunning: false,
        configuredClipboardPort: null,
        boundClipboardPort: null,
      );

      expect(plan.localHttpSettings, isNotNull);
      expect(plan.restartClipboard, isTrue);
      expect(plan.preferredClipboardPort, 12345);
    });
  });
}
