import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/services/webrtc_stats_summary.dart';

void main() {
  const builder = WebRtcStatsSummaryBuilder();

  test('detects selected candidate pairs', () {
    expect(builder.isSelectedCandidatePair({'selected': true}), isTrue);
    expect(
      builder.isSelectedCandidatePair({
        'nominated': true,
        'state': 'succeeded',
      }),
      isTrue,
    );
    expect(
      builder.isSelectedCandidatePair({
        'nominated': true,
        'state': 'in-progress',
      }),
      isFalse,
    );
  });

  test('detects audio stats reports', () {
    expect(
      builder.isAudioStatsReport('candidate-pair', {'kind': 'audio'}),
      isTrue,
    );
    expect(
      builder.isAudioStatsReport('candidate-pair', {'mediaType': 'audio'}),
      isTrue,
    );
    expect(builder.isAudioStatsReport('media-source', const {}), isTrue);
    expect(builder.isAudioStatsReport('inbound-rtp', const {}), isTrue);
    expect(builder.isAudioStatsReport('outbound-rtp', const {}), isTrue);
    expect(builder.isAudioStatsReport('candidate-pair', const {}), isFalse);
  });

  test('formats missing stats with fallback marker', () {
    expect(builder.stat({'bytesSent': 42}, 'bytesSent'), '42');
    expect(builder.stat(const {}, 'bytesSent'), '-');
    expect(builder.stat({'bytesSent': null}, 'bytesSent'), '-');
  });

  test('formats candidate pair and audio report summaries', () {
    expect(
      builder.candidatePairSummary('pair-1', {
        'state': 'succeeded',
        'nominated': true,
        'localCandidateId': 'local-1',
        'remoteCandidateId': 'remote-1',
        'bytesSent': 12,
        'bytesReceived': 34,
        'currentRoundTripTime': 0.1,
      }),
      'pair=pair-1 state=succeeded nominated=true local=local-1 remote=remote-1 sent=12 recv=34 rtt=0.1',
    );

    expect(
      builder.audioReportSummary('out-1', 'outbound-rtp', {
        'kind': 'audio',
        'packetsSent': 2,
        'bytesSent': 64,
      }),
      'outbound-rtp id=out-1 kind=audio media=- packetsSent=2 packetsRecv=- bytesSent=64 bytesRecv=- audioLevel=- totalAudioEnergy=-',
    );
  });
}
