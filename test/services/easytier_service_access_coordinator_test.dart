import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/services/easytier_service_access_coordinator.dart';

void main() {
  group('EasyTierServiceAccessCoordinator', () {
    const coordinator = EasyTierServiceAccessCoordinator();

    test('enableLocalHttpVpnExposure returns an infrastructure-free plan', () {
      final result = coordinator.enableLocalHttpVpnExposure(
        canConfigureLocalHttp: true,
      );

      expect(result, isNotNull);
      expect(result!.bindAllInterfaces, isTrue);
      expect(result.message, contains('3001'));
      expect(
        coordinator.enableLocalHttpVpnExposure(canConfigureLocalHttp: false),
        isNull,
      );
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
      final plan = coordinator.buildRestartPlan(
        localHttpEnabled: true,
        clipboardRunning: false,
        configuredClipboardPort: null,
        boundClipboardPort: null,
      );

      expect(plan.restartLocalHttp, isTrue);
      expect(plan.restartClipboard, isTrue);
      expect(plan.preferredClipboardPort, 12345);
    });
  });
}
