import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/application/remote_control_receiver_startup_coordinator.dart';

void main() {
  group('RemoteControlReceiverStartupCoordinator', () {
    test('runs native, control bind, then screen bind', () async {
      final events = <String>[];
      const coordinator = RemoteControlReceiverStartupCoordinator();

      await coordinator.start(
        enableScreen: true,
        startNativeReceiver: () async => events.add('native'),
        bindControlServer: () async => events.add('control'),
        bindScreenServer: () async => events.add('screen'),
        rollbackStartup: () async => events.add('rollback'),
      );

      expect(events, <String>['native', 'control', 'screen']);
    });

    test('skips screen bind when screen is disabled', () async {
      final events = <String>[];
      const coordinator = RemoteControlReceiverStartupCoordinator();

      await coordinator.start(
        enableScreen: false,
        startNativeReceiver: () async => events.add('native'),
        bindControlServer: () async => events.add('control'),
        bindScreenServer: () async => events.add('screen'),
        rollbackStartup: () async => events.add('rollback'),
      );

      expect(events, <String>['native', 'control']);
    });

    test('rolls back and logs when native start fails', () async {
      final events = <String>[];
      final logs = <String>[];
      const coordinator = RemoteControlReceiverStartupCoordinator();

      await expectLater(
        coordinator.start(
          enableScreen: true,
          startNativeReceiver: () async {
            events.add('native');
            throw StateError('native failed');
          },
          bindControlServer: () async => events.add('control'),
          bindScreenServer: () async => events.add('screen'),
          rollbackStartup: () async => events.add('rollback'),
          log: (message, {error}) => logs.add(message),
        ),
        throwsA(isA<StateError>()),
      );

      expect(events, <String>['native', 'rollback']);
      expect(logs.single, contains('Failed to start receiver'));
    });

    test('rolls back when control bind fails', () async {
      final events = <String>[];
      const coordinator = RemoteControlReceiverStartupCoordinator();

      await expectLater(
        coordinator.start(
          enableScreen: true,
          startNativeReceiver: () async => events.add('native'),
          bindControlServer: () async {
            events.add('control');
            throw StateError('control bind failed');
          },
          bindScreenServer: () async => events.add('screen'),
          rollbackStartup: () async => events.add('rollback'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(events, <String>['native', 'control', 'rollback']);
    });

    test('rolls back when screen bind fails', () async {
      final events = <String>[];
      const coordinator = RemoteControlReceiverStartupCoordinator();

      await expectLater(
        coordinator.start(
          enableScreen: true,
          startNativeReceiver: () async => events.add('native'),
          bindControlServer: () async => events.add('control'),
          bindScreenServer: () async {
            events.add('screen');
            throw StateError('screen bind failed');
          },
          rollbackStartup: () async => events.add('rollback'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(events, <String>['native', 'control', 'screen', 'rollback']);
    });
  });
}
