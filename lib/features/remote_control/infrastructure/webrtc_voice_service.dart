import 'dart:async';
import 'dart:io';

import '../domain/remote_control_protocol.dart';
import '../domain/webrtc_candidate_filter.dart';
import 'webrtc_voice_plugin_platform_gateway.dart';

typedef WebRtcSignalSender = Future<void> Function(StatusMessage message);
typedef WebRtcLogCallback = void Function(String message, {Object? error});
typedef WebRtcConnectionInterrupted = void Function(String reason);

class WebRtcVoiceService {
  static const WebRtcSdpSummary _sdpSummary = WebRtcSdpSummary();

  WebRtcVoiceService({
    required WebRtcSignalSender sendSignal,
    required Future<void> Function() ensureDiagnosticsLogging,
    required WebRtcLogCallback log,
    WebRtcConnectionInterrupted? onConnectionInterrupted,
    WebRtcVoicePluginPlatformGateway? plugin,
  }) : _sendSignal = sendSignal,
       _ensureDiagnosticsLogging = ensureDiagnosticsLogging,
       _log = log,
       _onConnectionInterrupted = onConnectionInterrupted,
       _plugin = plugin ?? WebRtcVoicePluginPlatformGateway.instance {
    _eventSubscription = _plugin.events.listen(_handlePluginEvent);
    _disconnectSubscription = _plugin.disconnects.listen((_) {
      _connected = false;
      _prepared = false;
      _localAudioEnabled = false;
      _onConnectionInterrupted?.call('plugin-disconnected');
    });
  }

  final WebRtcSignalSender _sendSignal;
  final Future<void> Function() _ensureDiagnosticsLogging;
  final WebRtcLogCallback _log;
  final WebRtcConnectionInterrupted? _onConnectionInterrupted;
  final WebRtcVoicePluginPlatformGateway _plugin;

  late final StreamSubscription<WebRtcPluginJson> _eventSubscription;
  late final StreamSubscription<void> _disconnectSubscription;
  bool _connected = false;
  bool _prepared = false;
  bool _localAudioEnabled = false;
  WebRtcNetworkPreference _networkPreference = const WebRtcNetworkPreference();
  String? _localOverlayHost;

  WebRtcCandidateFilter get _candidateFilter =>
      WebRtcCandidateFilter(preference: _networkPreference);

  bool get isLocalAudioEnabled => _localAudioEnabled;
  bool get isPrepared => _prepared;

  Future<void> prepare({
    required bool isController,
    WebRtcNetworkPreference networkPreference = const WebRtcNetworkPreference(),
  }) async {
    _networkPreference = networkPreference;
    _localOverlayHost = await _resolveLocalOverlayHost(networkPreference);
    if (_prepared) return;

    await _ensureDiagnosticsLogging();
    await _ensureConnected();
    if (!await _plugin.requestAudioPermission()) {
      throw StateError('远程语音插件未获得麦克风权限');
    }
    await _plugin.request(
      'prepare',
      arguments: <String, Object?>{'isController': isController},
    );
    _prepared = true;
    _localAudioEnabled = false;
    _log(
      'webrtc-plugin-prepared: controller=$isController preferenceHost=${networkPreference.preferredHost ?? 'none'} overlayPrefix=${networkPreference.preferredOverlayPrefix ?? 'none'}',
    );
  }

  Future<void> setLocalAudioEnabled(bool enabled) async {
    if (!_prepared) {
      if (!enabled) return;
      throw StateError('WebRTC voice session not prepared');
    }
    await _plugin.request(
      'setLocalAudioEnabled',
      arguments: <String, Object?>{'enabled': enabled},
    );
    _localAudioEnabled = enabled;
  }

  Future<void> handleSignal(
    StatusMessage message, {
    WebRtcNetworkPreference networkPreference = const WebRtcNetworkPreference(),
  }) async {
    if (networkPreference.preferredHost != null) {
      _networkPreference = networkPreference;
      _localOverlayHost ??= await _resolveLocalOverlayHost(networkPreference);
    }
    if (!_prepared && message.action == 'webrtc_offer') {
      await prepare(isController: false, networkPreference: _networkPreference);
    }
    if (!_prepared) {
      _log('webrtc-plugin-signal-ignored: not-prepared ${message.action}');
      return;
    }
    if (message.action == 'webrtc_candidate') {
      final candidate = message.data['candidate'] as String? ?? '';
      if (!_candidateFilter.shouldAcceptRemoteCandidate(
        candidate,
        log: (message) => _log(message),
      )) {
        _log(
          'webrtc-remote-candidate-skipped: ${_candidateFilter.summary(candidate)}',
        );
        return;
      }
    }
    await _plugin.request(
      'handleSignal',
      arguments: <String, Object?>{
        'action': message.action,
        'data': message.data,
      },
    );
  }

  Future<void> close() async {
    if (_connected) {
      try {
        await _plugin.request('close');
      } catch (error) {
        _log('webrtc-plugin-close-error', error: error);
      }
    }
    _prepared = false;
    _localAudioEnabled = false;
    _localOverlayHost = null;
    _log('webrtc-closed');
  }

  Future<void> _ensureConnected() async {
    if (_connected) return;
    _connected = await _plugin.connect();
    if (!_connected) {
      throw StateError('远程语音插件未安装、签名不匹配或版本不兼容');
    }
  }

  void _handlePluginEvent(WebRtcPluginJson event) {
    switch (event['type']) {
      case 'signal':
        unawaited(_forwardPluginSignal(event));
      case 'log':
        final message = event['message'] as String?;
        if (message != null && message.isNotEmpty) _log(message);
      case 'state':
        final data = event['data'];
        if (data is Map) {
          _prepared = data['prepared'] == true;
          _localAudioEnabled = data['localAudioEnabled'] == true;
        }
      case 'connectionInterrupted':
        final reason = event['reason'] as String? ?? 'unknown';
        _log('webrtc-connection-interrupted: $reason');
        _onConnectionInterrupted?.call(reason);
    }
  }

  Future<void> _forwardPluginSignal(WebRtcPluginJson event) async {
    final action = event['action'] as String?;
    final rawData = event['data'];
    if (action == null || rawData is! Map) return;
    final data = Map<String, dynamic>.from(rawData);
    if (action == 'webrtc_candidate') {
      final candidate = data['candidate'] as String? ?? '';
      if (!_candidateFilter.shouldSendLocalCandidate(
        candidate,
        log: (message) => _log(message),
      )) {
        _log(
          'webrtc-local-candidate-skipped: ${_candidateFilter.summary(candidate)}',
        );
        return;
      }
      final outbound = _candidateFilter.rewriteHostCandidateIp(
        candidate,
        replacementIp: _localOverlayHost,
        log: (message) => _log(message),
      );
      data['candidate'] = outbound;
      _log('webrtc-local-candidate: ${_candidateFilter.summary(outbound)}');
    } else {
      _log(
        'webrtc-${action == 'webrtc_offer' ? 'offer' : 'answer'}-created: ${_sdpSummary(data['sdp'] as String?)}',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _sendSignal(
      StatusMessage(action: action, data: data, id: now, timestamp: now),
    );
  }

  Future<String?> _resolveLocalOverlayHost(
    WebRtcNetworkPreference preference,
  ) async {
    final prefix = preference.preferredOverlayPrefix;
    if (!preference.preferOverlayHostCandidates || prefix == null) return null;
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.address.startsWith(prefix)) {
            _log(
              'webrtc-overlay-local-host: ${address.address} interface=${interface.name}',
            );
            return address.address;
          }
        }
      }
      _log('webrtc-overlay-local-host-missing: prefix=$prefix');
    } catch (error) {
      _log('webrtc-overlay-local-host-error', error: error);
    }
    return null;
  }

  Future<void> dispose() async {
    await close();
    await _eventSubscription.cancel();
    await _disconnectSubscription.cancel();
  }
}
