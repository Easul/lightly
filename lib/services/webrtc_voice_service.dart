import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'remote_control_protocol.dart';

typedef WebRtcSignalSender = Future<void> Function(StatusMessage message);
typedef WebRtcLogCallback = void Function(String message, {Object? error});

class WebRtcNetworkPreference {
  const WebRtcNetworkPreference({
    this.preferredHost,
    this.preferredOverlayPrefix,
  });

  final String? preferredHost;
  final String? preferredOverlayPrefix;

  bool get preferOverlayHostCandidates =>
      preferredHost != null &&
      preferredOverlayPrefix != null &&
      preferredHost!.startsWith(preferredOverlayPrefix!);
}

class WebRtcVoiceService {
  static const Map<String, dynamic> _audioConstraints = {
    'echoCancellation': true,
    'noiseSuppression': true,
    // 关闭软件 AGC，避免把远控通话放得过大；保留系统 AEC/NS。
    'autoGainControl': false,
    'googEchoCancellation': true,
    'googNoiseSuppression': true,
    'googAutoGainControl': false,
    'googHighpassFilter': true,
    'googTypingNoiseDetection': true,
    'channelCount': 1,
    'sampleRate': 48000,
    'sampleSize': 16,
  };

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
  bool _hasRemoteDescription = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  WebRtcNetworkPreference _networkPreference = const WebRtcNetworkPreference();
  Timer? _statsTimer;
  Timer? _audioRouteTimer;

  bool get isLocalAudioEnabled => _localAudioEnabled;
  bool get isPrepared => _peerConnection != null;

  Future<void> prepare({
    required bool isController,
    WebRtcNetworkPreference networkPreference = const WebRtcNetworkPreference(),
  }) async {
    _isController = isController;
    _networkPreference = networkPreference;
    if (_peerConnection != null) {
      return;
    }

    await _ensureDiagnosticsLogging();
    await _refreshAudioRoute();
    _startAudioRouteMonitor();

    final configuration = <String, dynamic>{
      'iceServers': const [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
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
      if (!_shouldSendLocalCandidate(candidateValue)) {
        _log(
          'webrtc-local-candidate-skipped: ${_candidateSummary(candidateValue)}',
        );
        return;
      }
      _log('webrtc-local-candidate: ${_candidateSummary(candidateValue)}');
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
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _startStatsTimer();
      }
    };
    peerConnection.onIceConnectionState = (state) {
      _log('webrtc-ice-state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _startStatsTimer();
      }
    };
    peerConnection.onTrack = (event) {
      if (event.track.kind == 'audio') {
        _log(
          'webrtc-remote-audio: track=${event.track.id} enabled=${event.track.enabled} muted=${event.track.muted} streams=${event.streams.length}',
        );
      }
    };

    final localStream = await navigator.mediaDevices.getUserMedia({
      'audio': _audioConstraints,
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
    _log(
      'webrtc-local-track-created: id=${localAudioTrack.id} enabled=${localAudioTrack.enabled} muted=${localAudioTrack.muted}',
    );

    _peerConnection = peerConnection;
    _localStream = localStream;
    _localAudioTrack = localAudioTrack;
    _localAudioEnabled = false;
    _hasRemoteDescription = false;
    _pendingRemoteCandidates.clear();

    _log(
      'webrtc-prepared: controller=$_isController track=${localAudioTrack.id} preferenceHost=${networkPreference.preferredHost ?? 'none'} overlayPrefix=${networkPreference.preferredOverlayPrefix ?? 'none'} preferOverlay=${networkPreference.preferOverlayHostCandidates}',
    );
    if (_isController) {
      await _createAndSendOffer();
    }
  }

  Future<void> setLocalAudioEnabled(bool enabled) async {
    if (_peerConnection == null) {
      if (!enabled) {
        return;
      }
      throw StateError('WebRTC voice session not prepared');
    }
    _localAudioEnabled = enabled;
    _localAudioTrack?.enabled = enabled;
    await _refreshAudioRoute();
    _log(
      'webrtc-local-audio: enabled=$enabled trackEnabled=${_localAudioTrack?.enabled} muted=${_localAudioTrack?.muted}',
    );
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
    _statsTimer?.cancel();
    _statsTimer = null;
    _audioRouteTimer?.cancel();
    _audioRouteTimer = null;
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
    _hasRemoteDescription = false;
    _pendingRemoteCandidates.clear();

    final peerConnection = _peerConnection;
    if (peerConnection != null) {
      await peerConnection.close();
      await peerConnection.dispose();
    }
    _peerConnection = null;

    await Helper.setSpeakerphoneOn(false);
    _log('webrtc-closed');
  }

  void _startAudioRouteMonitor() {
    _audioRouteTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshAudioRoute());
    });
  }

  Future<void> _refreshAudioRoute() async {
    try {
      final outputs = await Helper.audiooutputs;
      final inputs = await Helper.enumerateDevices('audioinput');
      final output = _preferredDevice(outputs);
      final input = _preferredDevice(inputs);
      if (output != null) {
        await Helper.selectAudioOutput(output.deviceId);
        _log('webrtc-audio-output: ${output.label}');
      } else if (_speakerphoneEnabled) {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
        _log('webrtc-audio-output: speaker-or-bluetooth');
      } else {
        await Helper.setSpeakerphoneOn(false);
      }
      if (input != null) {
        await Helper.selectAudioInput(input.deviceId);
        _log('webrtc-audio-input: ${input.label}');
      }
    } catch (error) {
      _log('webrtc-audio-route-error', error: error);
      if (_speakerphoneEnabled) {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
      }
    }
  }

  MediaDeviceInfo? _preferredDevice(List<MediaDeviceInfo> devices) {
    for (final keyword in const [
      'bluetooth',
      'headset',
      'headphone',
      'wired',
    ]) {
      for (final device in devices) {
        final label = device.label.toLowerCase();
        if (label.contains(keyword)) {
          return device;
        }
      }
    }
    return null;
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
    _log('webrtc-offer-created: ${_sdpSummary(offer.sdp)}');
    await _sendSignal(
      StatusMessage(
        action: 'webrtc_offer',
        data: {'sdp': offer.sdp, 'type': offer.type},
        id: DateTime.now().millisecondsSinceEpoch,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _log('webrtc-offer-sent: ${_sdpSummary(offer.sdp)}');
  }

  Future<void> _handleOffer(StatusMessage message) async {
    await prepare(isController: false, networkPreference: _networkPreference);
    final peerConnection = _peerConnection;
    if (peerConnection == null) {
      return;
    }

    final sdp = message.data['sdp'] as String?;
    final type = message.data['type'] as String? ?? 'offer';
    if (sdp == null || sdp.isEmpty) {
      _log('webrtc-offer-ignored: empty-sdp');
      return;
    }

    _log('webrtc-offer-received: ${_sdpSummary(sdp)}');
    await peerConnection.setRemoteDescription(RTCSessionDescription(sdp, type));
    _hasRemoteDescription = true;
    await _flushPendingRemoteCandidates();
    final answer = await peerConnection.createAnswer({
      'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': false},
      'optional': <Map<String, dynamic>>[],
    });
    await peerConnection.setLocalDescription(answer);
    _log('webrtc-answer-created: ${_sdpSummary(answer.sdp)}');
    await _sendSignal(
      StatusMessage(
        action: 'webrtc_answer',
        data: {'sdp': answer.sdp, 'type': answer.type},
        id: DateTime.now().millisecondsSinceEpoch,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _log('webrtc-answer-sent: ${_sdpSummary(answer.sdp)}');
  }

  Future<void> _handleAnswer(StatusMessage message) async {
    final peerConnection = _peerConnection;
    final sdp = message.data['sdp'] as String?;
    final type = message.data['type'] as String? ?? 'answer';
    if (peerConnection == null || sdp == null || sdp.isEmpty) {
      _log(
        'webrtc-answer-ignored: peer=${peerConnection != null} sdp=${sdp?.isNotEmpty == true}',
      );
      return;
    }
    _log('webrtc-answer-received: ${_sdpSummary(sdp)}');
    await peerConnection.setRemoteDescription(RTCSessionDescription(sdp, type));
    _hasRemoteDescription = true;
    await _flushPendingRemoteCandidates();
    _log('webrtc-answer-applied');
  }

  Future<void> _handleCandidate(StatusMessage message) async {
    final peerConnection = _peerConnection;
    if (peerConnection == null) {
      return;
    }

    final candidate = message.data['candidate'] as String?;
    if (candidate == null || candidate.isEmpty) {
      _log('webrtc-candidate-ignored: empty');
      return;
    }
    _log('webrtc-remote-candidate-received: ${_candidateSummary(candidate)}');

    final remoteCandidate = RTCIceCandidate(
      candidate,
      message.data['sdpMid'] as String?,
      message.data['sdpMLineIndex'] as int?,
    );
    if (!_shouldAcceptRemoteCandidate(candidate)) {
      _log('webrtc-remote-candidate-skipped: ${_candidateSummary(candidate)}');
      return;
    }
    if (!_hasRemoteDescription) {
      _pendingRemoteCandidates.add(remoteCandidate);
      _log('webrtc-candidate-queued: count=${_pendingRemoteCandidates.length}');
      return;
    }

    await peerConnection.addCandidate(remoteCandidate);
    _log('webrtc-candidate-applied: ${_candidateSummary(candidate)}');
  }

  Future<void> _flushPendingRemoteCandidates() async {
    final peerConnection = _peerConnection;
    if (peerConnection == null || _pendingRemoteCandidates.isEmpty) {
      return;
    }

    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      await peerConnection.addCandidate(candidate);
    }
    _log(
      'webrtc-candidate-flush: count=${pending.length} candidates=${pending.map((candidate) => _candidateSummary(candidate.candidate ?? '')).join(',')}',
    );
  }

  void _startStatsTimer() {
    if (_statsTimer != null) {
      return;
    }
    _log('webrtc-stats-started');
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_logStatsSnapshot());
    });
    unawaited(_logStatsSnapshot());
  }

  Future<void> _logStatsSnapshot() async {
    final peerConnection = _peerConnection;
    if (peerConnection == null) {
      return;
    }
    try {
      final reports = await peerConnection.getStats();
      final selectedPairs = <String>[];
      final audioReports = <String>[];
      for (final report in reports) {
        final values = report.values;
        final type = report.type;
        if (type == 'candidate-pair' && _isSelectedCandidatePair(values)) {
          selectedPairs.add(
            'pair=${report.id} state=${_stat(values, 'state')} nominated=${_stat(values, 'nominated')} local=${_stat(values, 'localCandidateId')} remote=${_stat(values, 'remoteCandidateId')} sent=${_stat(values, 'bytesSent')} recv=${_stat(values, 'bytesReceived')} rtt=${_stat(values, 'currentRoundTripTime')}',
          );
        }
        if (_isAudioStatsReport(type, values)) {
          audioReports.add(
            '$type id=${report.id} kind=${_stat(values, 'kind')} media=${_stat(values, 'mediaType')} packetsSent=${_stat(values, 'packetsSent')} packetsRecv=${_stat(values, 'packetsReceived')} bytesSent=${_stat(values, 'bytesSent')} bytesRecv=${_stat(values, 'bytesReceived')} audioLevel=${_stat(values, 'audioLevel')} totalAudioEnergy=${_stat(values, 'totalAudioEnergy')}',
          );
        }
      }
      _log(
        'webrtc-stats: selected=${selectedPairs.isEmpty ? 'none' : selectedPairs.join(' | ')} audio=${audioReports.isEmpty ? 'none' : audioReports.take(6).join(' | ')} localEnabled=$_localAudioEnabled trackEnabled=${_localAudioTrack?.enabled} trackMuted=${_localAudioTrack?.muted}',
      );
    } catch (error) {
      _log('webrtc-stats-error', error: error);
    }
  }

  bool _isSelectedCandidatePair(Map<dynamic, dynamic> values) {
    final selected = values['selected'];
    final nominated = values['nominated'];
    final state = values['state'];
    return selected == true || (nominated == true && state == 'succeeded');
  }

  bool _isAudioStatsReport(String type, Map<dynamic, dynamic> values) {
    final kind = values['kind']?.toString();
    final mediaType = values['mediaType']?.toString();
    return kind == 'audio' ||
        mediaType == 'audio' ||
        type == 'media-source' ||
        type == 'inbound-rtp' ||
        type == 'outbound-rtp';
  }

  String _stat(Map<dynamic, dynamic> values, String key) {
    final value = values[key];
    return value == null ? '-' : value.toString();
  }

  String _candidateKind(String candidate) {
    if (candidate.contains(' typ relay ')) {
      return 'relay';
    }
    if (candidate.contains(' typ srflx ')) {
      return 'srflx';
    }
    if (candidate.contains(' typ host ')) {
      return 'host';
    }
    return 'unknown';
  }

  bool _shouldSendLocalCandidate(String candidate) {
    if (!_networkPreference.preferOverlayHostCandidates) {
      return true;
    }
    if (_isPreferredOverlayCandidate(candidate)) {
      _log(
        'webrtc-overlay-candidate-available: ${_candidateSummary(candidate)}',
      );
    } else if (candidate.contains(' typ host ')) {
      _log(
        'webrtc-overlay-candidate-fallback: sending non-overlay ${_candidateSummary(candidate)}',
      );
    }
    return true;
  }

  bool _shouldAcceptRemoteCandidate(String candidate) {
    if (!_networkPreference.preferOverlayHostCandidates) {
      return true;
    }
    if (_isPreferredOverlayCandidate(candidate)) {
      _log('webrtc-overlay-remote-candidate: ${_candidateSummary(candidate)}');
    } else if (candidate.contains(' typ host ')) {
      _log(
        'webrtc-overlay-remote-fallback: accepting non-overlay ${_candidateSummary(candidate)}',
      );
    }
    return true;
  }

  bool _isPreferredOverlayCandidate(String candidate) {
    if (!candidate.contains(' typ host ')) {
      return false;
    }
    final ip = _extractCandidateIp(candidate);
    final preferredPrefix = _networkPreference.preferredOverlayPrefix;
    return ip != null &&
        preferredPrefix != null &&
        ip.startsWith(preferredPrefix);
  }

  String? _extractCandidateIp(String candidate) {
    final parts = candidate.split(' ');
    if (parts.length < 5) {
      return null;
    }
    return parts[4];
  }

  String? _extractCandidatePort(String candidate) {
    final parts = candidate.split(' ');
    if (parts.length < 6) {
      return null;
    }
    return parts[5];
  }

  String _candidateProtocol(String candidate) {
    final parts = candidate.split(' ');
    if (parts.length < 3) {
      return 'unknown';
    }
    return parts[2].toLowerCase();
  }

  String _candidateSummary(String candidate) {
    final kind = _candidateKind(candidate);
    final ip = _extractCandidateIp(candidate) ?? 'unknown';
    final port = _extractCandidatePort(candidate) ?? 'unknown';
    final protocol = _candidateProtocol(candidate);
    return '$kind/$protocol@$ip:$port';
  }

  String _sdpSummary(String? sdp) {
    if (sdp == null || sdp.isEmpty) {
      return 'empty';
    }
    final audioLineCount = '\nm=audio '.allMatches(sdp).length;
    final candidateCount = '\na=candidate:'.allMatches(sdp).length;
    final fingerprint = sdp.contains('\na=fingerprint:');
    final setup = RegExp(r'\na=setup:([^\r\n]+)').firstMatch(sdp)?.group(1);
    return 'chars=${sdp.length} audioM=$audioLineCount candidates=$candidateCount fingerprint=$fingerprint setup=${setup ?? '-'}';
  }
}
