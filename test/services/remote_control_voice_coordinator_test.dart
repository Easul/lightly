import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/services/remote_control_protocol.dart';
import 'package:lightly/services/remote_control_voice_coordinator.dart';
import 'package:lightly/services/webrtc_candidate_filter.dart';

void main() {
  group('RemoteControlVoiceCoordinator', () {
    late _VoiceHarness harness;

    setUp(() {
      harness = _VoiceHarness();
    });

    test('prepares session with overlay network preference', () async {
      await harness.coordinator.prepareSession(
        isVoiceEnabled: true,
        isController: true,
        targetHost: '10.126.126.1',
        overlayPrefix: '10.126.',
        log: harness.log,
      );

      expect(harness.prepareCalls, hasLength(1));
      expect(harness.prepareCalls.single.isController, isTrue);
      expect(
        harness.prepareCalls.single.preference.preferredHost,
        '10.126.126.1',
      );
      expect(
        harness.prepareCalls.single.preference.preferredOverlayPrefix,
        '10.126.',
      );
    });

    test('skips prepare and audio capture when voice is disabled', () async {
      await harness.coordinator.prepareSession(
        isVoiceEnabled: false,
        isController: true,
        targetHost: null,
        overlayPrefix: '10.126.',
        log: harness.log,
      );

      final started = await harness.coordinator.startAudioCapture(
        isVoiceEnabled: false,
        isController: true,
        targetHost: null,
        overlayPrefix: '10.126.',
        log: harness.log,
      );

      expect(started, isFalse);
      expect(harness.prepareCalls, isEmpty);
      expect(harness.audioEnabledCalls, isEmpty);
      expect(
        harness.logs,
        contains('Skipping WebRTC voice prepare: voice disabled'),
      );
    });

    test('starts and stops local audio capture', () async {
      harness.prepared = true;

      final started = await harness.coordinator.startAudioCapture(
        isVoiceEnabled: true,
        isController: false,
        targetHost: null,
        overlayPrefix: '10.126.',
        log: harness.log,
      );
      await harness.coordinator.stopAudioCapture();

      expect(started, isTrue);
      expect(harness.audioEnabledCalls, <bool>[true, false]);
    });

    test('routes webrtc signals only when voice is enabled', () {
      final message = StatusMessage(
        action: 'webrtc_offer',
        data: const {},
        id: 1,
        timestamp: 2,
      );

      final handledDisabled = harness.coordinator.handleIncomingWebRtcSignal(
        message: message,
        isVoiceEnabled: false,
        targetHost: '10.126.126.23',
        overlayPrefix: '10.126.',
        log: harness.log,
      );
      final handledEnabled = harness.coordinator.handleIncomingWebRtcSignal(
        message: message,
        isVoiceEnabled: true,
        targetHost: '10.126.126.23',
        overlayPrefix: '10.126.',
        log: harness.log,
      );

      expect(handledDisabled, isTrue);
      expect(handledEnabled, isTrue);
      expect(harness.signals, <StatusMessage>[message]);
      expect(harness.signalPreferences.single.preferredHost, '10.126.126.23');
      expect(
        harness.signalPreferences.single.preferredOverlayPrefix,
        '10.126.',
      );
      expect(
        harness.logs,
        contains('Ignoring WebRTC signal while voice disabled: webrtc_offer'),
      );
    });

    test('updates remote microphone status and emits message', () {
      final emitted = <ControlMessage>[];
      final message = StatusMessage.receiverMicrophoneStatus(enabled: true);

      final handled = harness.coordinator.handleReceiverMicrophoneStatus(
        message: message,
        emitMessage: emitted.add,
      );

      expect(handled, isTrue);
      expect(harness.coordinator.remoteMicrophoneEnabled, isTrue);
      expect(emitted, <ControlMessage>[message]);
    });

    test(
      'applies receiver microphone disabled status when voice is disabled',
      () async {
        final emitted = <ControlMessage>[];
        final sent = <StatusMessage>[];

        await harness.coordinator.applyReceiverMicrophone(
          enabled: true,
          isVoiceEnabled: false,
          targetHost: null,
          overlayPrefix: '10.126.',
          emitMessage: emitted.add,
          sendStatus: sent.add,
          log: harness.log,
        );

        expect(harness.coordinator.remoteMicrophoneEnabled, isFalse);
        expect((emitted.single as StatusMessage).data['enabled'], isFalse);
        expect(sent.single.data['enabled'], isFalse);
        expect(harness.audioEnabledCalls, isEmpty);
      },
    );

    test('applies receiver microphone through WebRTC audio track', () async {
      final emitted = <ControlMessage>[];
      final sent = <StatusMessage>[];

      await harness.coordinator.applyReceiverMicrophone(
        enabled: true,
        isVoiceEnabled: true,
        targetHost: '10.126.126.21',
        overlayPrefix: '10.126.',
        emitMessage: emitted.add,
        sendStatus: sent.add,
        log: harness.log,
      );

      expect(harness.prepareCalls.single.isController, isFalse);
      expect(harness.audioEnabledCalls, <bool>[true]);
      expect(harness.coordinator.remoteMicrophoneEnabled, isTrue);
      expect((emitted.single as StatusMessage).data['enabled'], isTrue);
      expect(sent.single.data['enabled'], isTrue);
    });

    test(
      'close resets remote microphone state and closes voice service',
      () async {
        harness.coordinator.handleReceiverMicrophoneStatus(
          message: StatusMessage.receiverMicrophoneStatus(enabled: true),
          emitMessage: (_) {},
        );

        await harness.coordinator.close();

        expect(harness.coordinator.remoteMicrophoneEnabled, isFalse);
        expect(harness.closeCount, 1);
      },
    );
  });
}

class _VoiceHarness {
  _VoiceHarness() {
    coordinator = RemoteControlVoiceCoordinator(
      prepare: ({required isController, required networkPreference}) async {
        prepareCalls.add(_PrepareCall(isController, networkPreference));
        prepared = true;
      },
      setLocalAudioEnabled: (enabled) async {
        audioEnabledCalls.add(enabled);
      },
      handleSignal: (message, {required networkPreference}) async {
        signals.add(message);
        signalPreferences.add(networkPreference);
      },
      close: () async {
        closeCount++;
        prepared = false;
      },
      isPrepared: () => prepared,
    );
  }

  late final RemoteControlVoiceCoordinator coordinator;
  final prepareCalls = <_PrepareCall>[];
  final audioEnabledCalls = <bool>[];
  final signals = <StatusMessage>[];
  final signalPreferences = <WebRtcNetworkPreference>[];
  final logs = <String>[];
  var closeCount = 0;
  var prepared = false;

  void log(String message, {Object? error}) {
    logs.add(message);
  }
}

class _PrepareCall {
  const _PrepareCall(this.isController, this.preference);

  final bool isController;
  final WebRtcNetworkPreference preference;
}
