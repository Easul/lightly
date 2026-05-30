typedef WebRtcCandidateLogCallback = void Function(String message);

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

class WebRtcCandidateFilter {
  const WebRtcCandidateFilter({required this.preference});

  final WebRtcNetworkPreference preference;

  bool shouldSendLocalCandidate(
    String candidate, {
    WebRtcCandidateLogCallback? log,
  }) {
    _logOverlayDecision(
      candidate,
      log: log,
      preferredMessagePrefix: 'webrtc-overlay-candidate-available',
      fallbackMessagePrefix:
          'webrtc-overlay-candidate-fallback: sending non-overlay',
    );
    return true;
  }

  bool shouldAcceptRemoteCandidate(
    String candidate, {
    WebRtcCandidateLogCallback? log,
  }) {
    _logOverlayDecision(
      candidate,
      log: log,
      preferredMessagePrefix: 'webrtc-overlay-remote-candidate',
      fallbackMessagePrefix:
          'webrtc-overlay-remote-fallback: accepting non-overlay',
    );
    return true;
  }

  String rewriteHostCandidateIp(
    String candidate, {
    required String? replacementIp,
    WebRtcCandidateLogCallback? log,
  }) {
    if (replacementIp == null ||
        replacementIp.isEmpty ||
        kind(candidate) != 'host') {
      return candidate;
    }
    final parts = candidate.split(' ');
    if (parts.length < 5) {
      return candidate;
    }
    final originalIp = parts[4];
    if (originalIp == replacementIp) {
      return candidate;
    }
    parts[4] = replacementIp;
    final rewritten = parts.join(' ');
    log?.call(
      'webrtc-overlay-candidate-rewritten: ${summary(candidate)} -> ${summary(rewritten)}',
    );
    return rewritten;
  }

  void _logOverlayDecision(
    String candidate, {
    required WebRtcCandidateLogCallback? log,
    required String preferredMessagePrefix,
    required String fallbackMessagePrefix,
  }) {
    if (!preference.preferOverlayHostCandidates || log == null) {
      return;
    }
    final candidateSummary = summary(candidate);
    if (isPreferredOverlayCandidate(candidate)) {
      log('$preferredMessagePrefix: $candidateSummary');
    } else if (kind(candidate) == 'host') {
      log('$fallbackMessagePrefix $candidateSummary');
    }
  }

  bool isPreferredOverlayCandidate(String candidate) {
    if (kind(candidate) != 'host') {
      return false;
    }
    final ip = extractIp(candidate);
    final preferredPrefix = preference.preferredOverlayPrefix;
    return ip != null &&
        preferredPrefix != null &&
        ip.startsWith(preferredPrefix);
  }

  String summary(String candidate) {
    final candidateKind = kind(candidate);
    final ip = extractIp(candidate) ?? 'unknown';
    final port = extractPort(candidate) ?? 'unknown';
    final candidateProtocol = protocol(candidate);
    return '$candidateKind/$candidateProtocol@$ip:$port';
  }

  String kind(String candidate) {
    final parts = candidate.split(' ');
    final typeMarkerIndex = parts.indexOf('typ');
    if (typeMarkerIndex >= 0 && typeMarkerIndex + 1 < parts.length) {
      return parts[typeMarkerIndex + 1].toLowerCase();
    }
    return 'unknown';
  }

  String? extractIp(String candidate) {
    final parts = candidate.split(' ');
    if (parts.length < 5) {
      return null;
    }
    return parts[4];
  }

  String? extractPort(String candidate) {
    final parts = candidate.split(' ');
    if (parts.length < 6) {
      return null;
    }
    return parts[5];
  }

  String protocol(String candidate) {
    final parts = candidate.split(' ');
    if (parts.length < 3) {
      return 'unknown';
    }
    return parts[2].toLowerCase();
  }
}

class WebRtcSdpSummary {
  const WebRtcSdpSummary();

  String call(String? sdp) {
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
