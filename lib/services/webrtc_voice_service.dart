import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'remote_control_protocol.dart';

typedef WebRtcSignalSender = Future<void> Function(StatusMessage message);
typedef WebRtcLogCallback = void Function(String message, {Object? error});

class WebRtcVoiceService {
  WebRtcVoiceService({
    required WebRtcSignalSender sendSignal,
    required Future<void> Function() ensureDiagnosticsLogging,
    required WebRtcLogCallback log,
  }) : _sendSignal = sendSignal,
       _ensureDiagnosticsLogging = ensureDiagnosticsLogging,
       _log = log;

  final WebRtcSignalSender _sendSignal;
  final Future<void> Function() _ensureDiagnosticsLogging;
  final WebRtcLogCallback _log;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStreamTrack? _localAudioTrack;
  bool _localAudioEnabled = false;
  bool _isController = false;
  final bool _speakerphoneEnabled = true;

  bool get isLocalAudioEnabled => _localAudioEnabled;
  bool get isPrepared => _peerConnection != null;

  Future<void> prepare({required bool isController}) async {
    _isController = isController;
    if (_peerConnection != null) {
      return;
    }

    await _ensureDiagnosticsLogging();
    await Helper.setSpeakerphoneOn(_speakerphoneEnabled);

    final configuration = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    final constraints = <String, dynamic>{
      'mandatory': <String, dynamic>{},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    };

    final peerConnection = await createPeerConnection(
      configuration,
      constraints,
    );
    peerConnection.onIceCandidate = (candidate) {
      final candidateValue = candidate.candidate;
      if (candidateValue == null || candidateValue.isEmpty) {
        return;
      }
      unawaited(
        _sendSignal(
          StatusMessage(
            action: 'webrtc_candidate',
            data: {
              'candidate': candidateValue,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
            id: DateTime.now().millisecondsSinceEpoch,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
    };
    peerConnection.onConnectionState = (state) {
      _log('webrtc-state: $state');
    };
    peerConnection.onIceConnectionState = (state) {
      _log('webrtc-ice-state: $state');
    };
    peerConnection.onTrack = (event) {
      if (event.track.kind == 'audio') {
        _log(
          'webrtc-remote-audio: track=${event.track.id} streams=${event.streams.length}',
        );
      }
    };

    final localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    final audioTracks = localStream.getAudioTracks();
    if (audioTracks.isEmpty) {
      await localStream.dispose();
      await peerConnection.close();
      throw StateError('WebRTC local audio track not found');
    }

    final localAudioTrack = audioTracks.first;
    localAudioTrack.enabled = false;
    await peerConnection.addTrack(localAudioTrack, localStream);

    _peerConnection = peerConnection;
    _localStream = localStream;
    _localAudioTrack = localAudioTrack;
    _localAudioEnabled = false;

    _log(
      'webrtc-prepared: controller=$_isController track=${localAudioTrack.id}',
    );
    if (_isController) {
      await _createAndSendOffer();
    }
  }

  Future<void> setLocalAudioEnabled(bool enabled) async {
    if (_peerConnection == null) {
      await prepare(isController: _isController);
    }
    _localAudioEnabled = enabled;
    _localAudioTrack?.enabled = enabled;
    await Helper.setSpeakerphoneOn(_speakerphoneEnabled);
    _log('webrtc-local-audio: enabled=$enabled');
  }

  Future<void> handleSignal(StatusMessage message) async {
    switch (message.action) {
      case 'webrtc_offer':
        await _handleOffer(message);
        break;
      case 'webrtc_answer':
        await _handleAnswer(message);
        break;
      case 'webrtc_candidate':
        await _handleCandidate(message);
        break;
    }
  }

  Future<void> close() async {
    _localAudioEnabled = false;
    _localAudioTrack?.enabled = false;

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
    _localStream = null;
    _localAudioTrack = null;

    final peerConnection = _peerConnection;
    if (peerConnection != null) {
      await peerConnection.close();
      await peerConnection.dispose();
    }
    _peerConnection = null;

    await Helper.setSpeakerphoneOn(false);
    _log('webrtc-closed');
  }

  Future<void> _createAndSendOffer() async {
    final peerConnection = _peerConnection;
    if (peerConnection == null) {
      return;
    }
    final offer = await peerConnection.createOffer({
      'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': false},
      'optional': <Map<String, dynamic>>[],
    });
    await peerConnection.setLocalDescription(offer);
    await _sendSignal(
      StatusMessage(
        action: 'webrtc_offer',
        data: {'sdp': offer.sdp, 'type': offer.type},
        id: DateTime.now().millisecondsSinceEpoch,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _log('webrtc-offer-sent');
  }

  Future<void> _handleOffer(StatusMessage message) async {
    await prepare(isController: false);
    final peerConnection = _peerConnection;
    if (peerConnection == null) {
      return;
    }

    final sdp = message.data['sdp'] as String?;
    final type = message.data['type'] as String? ?? 'offer';
    if (sdp == null || sdp.isEmpty) {
      return;
    }

    await peerConnection.setRemoteDescription(RTCSessionDescription(sdp, type));
    final answer = await peerConnection.createAnswer({
      'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': false},
      'optional': <Map<String, dynamic>>[],
    });
    await peerConnection.setLocalDescription(answer);
    await _sendSignal(
      StatusMessage(
        action: 'webrtc_answer',
        data: {'sdp': answer.sdp, 'type': answer.type},
        id: DateTime.now().millisecondsSinceEpoch,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _log('webrtc-answer-sent');
  }

  Future<void> _handleAnswer(StatusMessage message) async {
    final peerConnection = _peerConnection;
    final sdp = message.data['sdp'] as String?;
    final type = message.data['type'] as String? ?? 'answer';
    if (peerConnection == null || sdp == null || sdp.isEmpty) {
      return;
    }
    await peerConnection.setRemoteDescription(RTCSessionDescription(sdp, type));
    _log('webrtc-answer-applied');
  }

  Future<void> _handleCandidate(StatusMessage message) async {
    final peerConnection = _peerConnection;
    if (peerConnection == null) {
      return;
    }

    final candidate = message.data['candidate'] as String?;
    if (candidate == null || candidate.isEmpty) {
      return;
    }

    await peerConnection.addCandidate(
      RTCIceCandidate(
        candidate,
        message.data['sdpMid'] as String?,
        message.data['sdpMLineIndex'] as int?,
      ),
    );
    _log('webrtc-candidate-applied');
  }
}
