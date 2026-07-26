import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/application/remote_control_recovery_helper.dart';
import 'package:lightly/features/remote_control/application/remote_control_screen_health_coordinator.dart';
import 'package:lightly/features/remote_control/application/remote_control_watchdog_controller.dart';
import 'package:lightly/features/remote_control/domain/screen_frame.dart';

void main() {
  group('RemoteControlScreenHealthCoordinator', () {
    test('records chunks and exposes frame age description', () {
      final health = RemoteControlScreenHealthCoordinator();

      expect(health.lastFrameAgeDescription, 'never');

      health.recordScreenChunk(
        data: Uint8List.fromList(<int>[1, 2, 3]),
        bufferedBefore: 0,
        log: (_) {},
      );
      health.recordParsedFrame(
        frame: ScreenFrame(
          type: ScreenFrameType.keyFrame,
          data: Uint8List.fromList(<int>[1]),
          timestamp: 1,
        ),
        remainingBuffer: 0,
        log: (_) {},
        onBitrateAdjustDue: () {},
      );

      expect(health.lastFrameAgeDescription, endsWith('ms'));
    });

    test('marks awaiting recovery from pipeline state', () {
      final health = RemoteControlScreenHealthCoordinator();

      expect(health.awaitingRecoveryKeyFrame, isFalse);

      health.markAwaitingRecoveryKeyFrame(true);
      expect(health.awaitingRecoveryKeyFrame, isTrue);

      health.markAwaitingRecoveryKeyFrame(false);
      expect(health.awaitingRecoveryKeyFrame, isFalse);
    });

    test(
      'requests key frame when watchdog startup exceeds stall threshold',
      () async {
        final health = RemoteControlScreenHealthCoordinator();
        health.startWatchdog(
          log: (_) {},
          onTick: () {},
          screenFrameStallThreshold: const Duration(milliseconds: 5),
          screenKeyFrameRequestCooldown: const Duration(milliseconds: 1000),
          screenRecoveryKeyFrameRetryCooldown: const Duration(
            milliseconds: 450,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));

        final shouldRequest = health.shouldRequestKeyFrame(
          screenRecoveryKeyFrameRetryCooldown: const Duration(
            milliseconds: 450,
          ),
          screenKeyFrameRequestCooldown: const Duration(milliseconds: 1000),
          screenFrameStallThreshold: const Duration(milliseconds: 5),
          screenDataBufferLength: 0,
          log: (_) {},
        );

        expect(shouldRequest, isTrue);
        expect(health.awaitingRecoveryKeyFrame, isTrue);
        health.stopWatchdog(log: (_) {}, bufferLength: 0);
      },
    );

    test('respects key frame request cooldown', () async {
      final health = RemoteControlScreenHealthCoordinator();
      health.startWatchdog(
        log: (_) {},
        onTick: () {},
        screenFrameStallThreshold: const Duration(milliseconds: 5),
        screenKeyFrameRequestCooldown: const Duration(milliseconds: 1000),
        screenRecoveryKeyFrameRetryCooldown: const Duration(milliseconds: 450),
      );
      health.recordKeyFrameRequest(DateTime.now());

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final shouldRequest = health.shouldRequestKeyFrame(
        screenRecoveryKeyFrameRetryCooldown: const Duration(milliseconds: 450),
        screenKeyFrameRequestCooldown: const Duration(milliseconds: 1000),
        screenFrameStallThreshold: const Duration(milliseconds: 5),
        screenDataBufferLength: 0,
        log: (_) {},
      );

      expect(shouldRequest, isFalse);
      health.stopWatchdog(log: (_) {}, bufferLength: 0);
    });

    test('adjusts bitrate through wrapped watchdog controller', () {
      final health = RemoteControlScreenHealthCoordinator(
        watchdog: RemoteControlWatchdogController(
          recoveryHelper: const RemoteControlRecoveryHelper(),
          initialBitrate: 1000000,
        ),
      );

      for (var i = 0; i < 11; i++) {
        health.recordParsedFrame(
          frame: ScreenFrame(
            type: ScreenFrameType.deltaFrame,
            data: Uint8List.fromList(<int>[i]),
            timestamp: i,
          ),
          remainingBuffer: 0,
          log: (_) {},
          onBitrateAdjustDue: () {},
        );
      }

      final newBitrate = health.adjustBitrateIfNeeded(
        screenFps: 15,
        maxBitrate: 8000000,
        latestRemoteScreenInfo: const <String, dynamic>{
          'width': 720,
          'height': 1280,
        },
        log: (_) {},
      );

      expect(newBitrate, greaterThanOrEqualTo(800000));
      expect(newBitrate, lessThanOrEqualTo(8000000));
    });
  });
}
