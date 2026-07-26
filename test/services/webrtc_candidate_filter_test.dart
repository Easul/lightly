import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/remote_control/domain/webrtc_candidate_filter.dart';

void main() {
  const hostCandidate =
      'candidate:1 1 UDP 2122252543 10.126.126.21 54321 typ host';
  const localHostCandidate =
      'candidate:2 1 UDP 2122252543 192.168.1.10 45678 typ host';
  const srflxCandidate =
      'candidate:3 1 udp 1686052607 8.8.8.8 3478 typ srflx raddr 0.0.0.0 rport 0';
  const relayCandidate =
      'candidate:4 1 tcp 1518280447 1.2.3.4 443 typ relay tcptype passive';

  group('WebRtcCandidateFilter', () {
    test('summarizes candidate kind protocol address and port', () {
      const filter = WebRtcCandidateFilter(
        preference: WebRtcNetworkPreference(),
      );

      expect(filter.summary(hostCandidate), 'host/udp@10.126.126.21:54321');
      expect(filter.summary(srflxCandidate), 'srflx/udp@8.8.8.8:3478');
      expect(filter.summary(relayCandidate), 'relay/tcp@1.2.3.4:443');
      expect(
        filter.summary('candidate:bad'),
        'unknown/unknown@unknown:unknown',
      );
    });

    test('detects preferred overlay host candidates', () {
      const filter = WebRtcCandidateFilter(
        preference: WebRtcNetworkPreference(
          preferredHost: '10.126.126.1',
          preferredOverlayPrefix: '10.126.',
        ),
      );

      expect(filter.isPreferredOverlayCandidate(hostCandidate), isTrue);
      expect(filter.isPreferredOverlayCandidate(localHostCandidate), isFalse);
      expect(filter.isPreferredOverlayCandidate(srflxCandidate), isFalse);
    });

    test('keeps candidates available while logging overlay preference', () {
      final logs = <String>[];
      const filter = WebRtcCandidateFilter(
        preference: WebRtcNetworkPreference(
          preferredHost: '10.126.126.1',
          preferredOverlayPrefix: '10.126.',
        ),
      );

      expect(
        filter.shouldSendLocalCandidate(hostCandidate, log: logs.add),
        isTrue,
      );
      expect(
        filter.shouldSendLocalCandidate(localHostCandidate, log: logs.add),
        isTrue,
      );
      expect(
        filter.shouldAcceptRemoteCandidate(localHostCandidate, log: logs.add),
        isTrue,
      );

      expect(
        logs,
        containsAll(<String>[
          'webrtc-overlay-candidate-available: host/udp@10.126.126.21:54321',
          'webrtc-overlay-candidate-fallback: sending non-overlay host/udp@192.168.1.10:45678',
          'webrtc-overlay-remote-fallback: accepting non-overlay host/udp@192.168.1.10:45678',
        ]),
      );
    });

    test('rewrites host candidate ip for overlay advertisement', () {
      final logs = <String>[];
      const filter = WebRtcCandidateFilter(
        preference: WebRtcNetworkPreference(
          preferredHost: '10.126.126.1',
          preferredOverlayPrefix: '10.126.',
        ),
      );

      final rewritten = filter.rewriteHostCandidateIp(
        localHostCandidate,
        replacementIp: '10.126.126.23',
        log: logs.add,
      );

      expect(
        rewritten,
        'candidate:2 1 UDP 2122252543 10.126.126.23 45678 typ host',
      );
      expect(
        logs.single,
        'webrtc-overlay-candidate-rewritten: host/udp@192.168.1.10:45678 -> host/udp@10.126.126.23:45678',
      );
    });

    test('does not rewrite non-host or missing replacement candidates', () {
      const filter = WebRtcCandidateFilter(
        preference: WebRtcNetworkPreference(
          preferredHost: '10.126.126.1',
          preferredOverlayPrefix: '10.126.',
        ),
      );

      expect(
        filter.rewriteHostCandidateIp(
          srflxCandidate,
          replacementIp: '10.126.126.23',
        ),
        srflxCandidate,
      );
      expect(
        filter.rewriteHostCandidateIp(localHostCandidate, replacementIp: null),
        localHostCandidate,
      );
    });
  });

  group('WebRtcSdpSummary', () {
    test('summarizes empty and populated SDP', () {
      const summary = WebRtcSdpSummary();

      expect(summary(null), 'empty');
      expect(summary(''), 'empty');

      const sdp =
          'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=setup:actpass\r\n'
          'a=fingerprint:sha-256 AA:BB\r\n'
          'a=candidate:1 1 UDP 1 10.126.126.21 54321 typ host\r\n';

      expect(
        summary(sdp),
        'chars=${sdp.length} audioM=1 candidates=1 fingerprint=true setup=actpass',
      );
    });
  });
}
