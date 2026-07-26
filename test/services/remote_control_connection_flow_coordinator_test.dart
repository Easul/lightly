import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/application/remote_control_connection_flow_coordinator.dart';

void main() {
  group('RemoteControlConnectionFlowCoordinator', () {
    test('succeeds when attempt marks ready', () async {
      late RemoteControlConnectionFlowCoordinator coordinator;
      final attempts = <int>[];
      final resets = <bool>[];
      final delays = <Duration>[];
      var prepared = 0;

      coordinator = RemoteControlConnectionFlowCoordinator(
        readyTimeout: const Duration(milliseconds: 20),
        delay: (duration) async {
          delays.add(duration);
        },
      );

      await coordinator.connect(
        prepareAttempt: (attempt) {
          prepared++;
        },
        attemptConnection: (attempt, markNativeStarted) async {
          attempts.add(attempt);
          markNativeStarted();
          coordinator.markReady();
        },
        resetConnection: ({required stopNative}) async {
          resets.add(stopNative);
        },
      );

      expect(prepared, 1);
      expect(attempts, <int>[0]);
      expect(resets, isEmpty);
      expect(delays, isEmpty);
    });

    test('retries with expected backoff after failed attempts', () async {
      late RemoteControlConnectionFlowCoordinator coordinator;
      final attempts = <int>[];
      final resets = <bool>[];
      final delays = <Duration>[];

      coordinator = RemoteControlConnectionFlowCoordinator(
        readyTimeout: const Duration(milliseconds: 20),
        delay: (duration) async {
          delays.add(duration);
        },
      );

      await coordinator.connect(
        prepareAttempt: (_) {},
        attemptConnection: (attempt, markNativeStarted) async {
          attempts.add(attempt);
          if (attempt < 2) {
            throw StateError('socket failed $attempt');
          }
          markNativeStarted();
          coordinator.markReady();
        },
        resetConnection: ({required stopNative}) async {
          resets.add(stopNative);
        },
      );

      expect(attempts, <int>[0, 1, 2]);
      expect(resets, <bool>[false, false]);
      expect(delays, <Duration>[
        const Duration(milliseconds: 350),
        const Duration(milliseconds: 700),
      ]);
    });

    test(
      'ready timeout resets native controller when native already started',
      () async {
        final resets = <bool>[];
        final logs = <String>[];
        final coordinator = RemoteControlConnectionFlowCoordinator(
          maxAttempts: 1,
          readyTimeout: const Duration(milliseconds: 1),
          delay: (_) async {},
        );

        await expectLater(
          coordinator.connect(
            prepareAttempt: (_) {},
            attemptConnection: (_, markNativeStarted) async {
              markNativeStarted();
            },
            resetConnection: ({required stopNative}) async {
              resets.add(stopNative);
            },
            log: (message, {error}) {
              logs.add(message);
            },
          ),
          throwsA(isA<TimeoutException>()),
        );

        expect(resets, <bool>[true]);
        expect(logs.single, contains('Connect attempt 1 failed'));
      },
    );

    test(
      'native start failure resets sockets without stopping native',
      () async {
        final resets = <bool>[];
        final coordinator = RemoteControlConnectionFlowCoordinator(
          maxAttempts: 1,
          readyTimeout: const Duration(milliseconds: 20),
          delay: (_) async {},
        );

        await expectLater(
          coordinator.connect(
            prepareAttempt: (_) {},
            attemptConnection: (_, markNativeStarted) async {
              throw StateError('native start failed');
            },
            resetConnection: ({required stopNative}) async {
              resets.add(stopNative);
            },
          ),
          throwsA(isA<StateError>()),
        );

        expect(resets, <bool>[false]);
      },
    );

    test(
      'late markReady is ignored after a failed attempt is cleared',
      () async {
        final coordinator = RemoteControlConnectionFlowCoordinator(
          maxAttempts: 1,
          readyTimeout: const Duration(milliseconds: 1),
          delay: (_) async {},
        );

        await expectLater(
          coordinator.connect(
            prepareAttempt: (_) {},
            attemptConnection: (_, markNativeStarted) async {},
            resetConnection: ({required stopNative}) async {},
          ),
          throwsA(isA<TimeoutException>()),
        );

        expect(coordinator.markReady, returnsNormally);
      },
    );

    test('retryDelayForAttempt preserves existing timing', () {
      final coordinator = RemoteControlConnectionFlowCoordinator();

      expect(
        coordinator.retryDelayForAttempt(0),
        const Duration(milliseconds: 350),
      );
      expect(
        coordinator.retryDelayForAttempt(1),
        const Duration(milliseconds: 700),
      );
      expect(
        coordinator.retryDelayForAttempt(2),
        const Duration(milliseconds: 1050),
      );
    });
  });
}
