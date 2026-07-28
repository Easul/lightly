import '../domain/remote_control_protocol.dart';
import '../domain/webrtc_candidate_filter.dart';

typedef RemoteVoicePrepare =
    Future<void> Function({
      required bool isController,
      required WebRtcNetworkPreference networkPreference,
    });
typedef RemoteVoiceSetLocalAudio = Future<void> Function(bool enabled);
typedef RemoteVoiceHandleSignal =
    Future<void> Function(
      StatusMessage message, {
      required WebRtcNetworkPreference networkPreference,
    });
typedef RemoteVoiceClose = Future<void> Function();
typedef RemoteVoiceLog = void Function(String message, {Object? error});
typedef RemoteVoiceEmit = void Function(ControlMessage message);
typedef RemoteVoiceSendStatus = void Function(StatusMessage message);

class RemoteControlVoiceCoordinator {
  RemoteControlVoiceCoordinator({
    required RemoteVoicePrepare prepare,
    required RemoteVoiceSetLocalAudio setLocalAudioEnabled,
    required RemoteVoiceHandleSignal handleSignal,
    required RemoteVoiceClose close,
    required bool Function() isPrepared,
  }) : _prepare = prepare,
       _setLocalAudioEnabled = setLocalAudioEnabled,
       _handleSignal = handleSignal,
       _close = close,
       _isPrepared = isPrepared;

  final RemoteVoicePrepare _prepare;
  final RemoteVoiceSetLocalAudio _setLocalAudioEnabled;
  final RemoteVoiceHandleSignal _handleSignal;
  final RemoteVoiceClose _close;
  final bool Function() _isPrepared;

  bool _remoteMicrophoneEnabled = false;

  bool get remoteMicrophoneEnabled => _remoteMicrophoneEnabled;

  bool isWebRtcSignal(StatusMessage message) {
    return message.action == 'webrtc_offer' ||
        message.action == 'webrtc_answer' ||
        message.action == 'webrtc_candidate';
  }

  Future<void> prepareSession({
    required bool isVoiceEnabled,
    required bool isController,
    required String? targetHost,
    required String overlayPrefix,
    required RemoteVoiceLog log,
  }) async {
    if (!isVoiceEnabled) {
      log('Skipping WebRTC voice prepare: voice disabled');
      return;
    }
    log(
      'Preparing WebRTC voice: controller=$isController targetHost=${targetHost ?? 'none'}',
    );
    await _prepare(
      isController: isController,
      networkPreference: WebRtcNetworkPreference(
        preferredHost: targetHost,
        preferredOverlayPrefix: overlayPrefix,
      ),
    );
  }

  Future<bool> startAudioCapture({
    required bool isVoiceEnabled,
    required bool isController,
    required String? targetHost,
    required String overlayPrefix,
    required RemoteVoiceLog log,
  }) async {
    if (!isVoiceEnabled) {
      log('Skipping audio capture: voice disabled for this session');
      return false;
    }
    try {
      await prepareSession(
        isVoiceEnabled: isVoiceEnabled,
        isController: isController,
        targetHost: targetHost,
        overlayPrefix: overlayPrefix,
        log: log,
      );
      await _setLocalAudioEnabled(true);
      return true;
    } catch (error) {
      log('Failed to start audio capture: $error', error: error);
      return false;
    }
  }

  Future<void> stopAudioCapture() async {
    if (!_isPrepared()) {
      return;
    }
    await _setLocalAudioEnabled(false);
  }

  Future<void> startAudioPlayback({
    required bool isVoiceEnabled,
    required bool isController,
    required String? targetHost,
    required String overlayPrefix,
    required RemoteVoiceLog log,
  }) async {
    if (!isVoiceEnabled) {
      return;
    }
    await prepareSession(
      isVoiceEnabled: isVoiceEnabled,
      isController: isController,
      targetHost: targetHost,
      overlayPrefix: overlayPrefix,
      log: log,
    );
  }

  Future<void> stopAudioPlayback() async {
    await _close();
  }

  Future<void> close() async {
    _remoteMicrophoneEnabled = false;
    await _close();
  }

  bool handleIncomingWebRtcSignal({
    required StatusMessage message,
    required bool isVoiceEnabled,
    required String? targetHost,
    required String overlayPrefix,
    required RemoteVoiceLog log,
  }) {
    if (!isWebRtcSignal(message)) {
      return false;
    }
    if (!isVoiceEnabled) {
      log('Ignoring WebRTC signal while voice disabled: ${message.action}');
      return true;
    }
    log(
      'Received WebRTC signal: ${message.action} targetHost=${targetHost ?? 'none'}',
    );
    _handleSignal(
      message,
      networkPreference: WebRtcNetworkPreference(
        preferredHost: targetHost,
        preferredOverlayPrefix: overlayPrefix,
      ),
    ).catchError((Object error) {
      log('Failed to handle WebRTC signal: $error', error: error);
    });
    return true;
  }

  bool handleReceiverMicrophoneStatus({
    required StatusMessage message,
    required RemoteVoiceEmit emitMessage,
  }) {
    if (message.action != 'receiver_microphone_status') {
      return false;
    }
    _remoteMicrophoneEnabled = message.data['enabled'] == true;
    emitMessage(message);
    return true;
  }

  Future<void> applyReceiverMicrophone({
    required bool enabled,
    required bool isVoiceEnabled,
    required String? targetHost,
    required String overlayPrefix,
    required RemoteVoiceEmit emitMessage,
    required RemoteVoiceSendStatus sendStatus,
    required RemoteVoiceLog log,
  }) async {
    try {
      if (!isVoiceEnabled) {
        final status = StatusMessage.receiverMicrophoneStatus(enabled: false);
        _remoteMicrophoneEnabled = false;
        emitMessage(status);
        sendStatus(status);
        return;
      }
      await prepareSession(
        isVoiceEnabled: isVoiceEnabled,
        isController: false,
        targetHost: targetHost,
        overlayPrefix: overlayPrefix,
        log: log,
      );
      await _setLocalAudioEnabled(enabled);
      final status = StatusMessage.receiverMicrophoneStatus(enabled: enabled);
      _remoteMicrophoneEnabled = enabled;
      emitMessage(status);
      sendStatus(status);
    } catch (error) {
      log('Failed to set receiver microphone: $error', error: error);
    }
  }
}
