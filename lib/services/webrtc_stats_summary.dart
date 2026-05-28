import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRtcStatsSnapshotSummary {
  const WebRtcStatsSnapshotSummary({
    required this.selected,
    required this.audio,
  });

  final String selected;
  final String audio;
}

class WebRtcStatsSummaryBuilder {
  const WebRtcStatsSummaryBuilder();

  WebRtcStatsSnapshotSummary build(List<StatsReport> reports) {
    final selectedPairs = <String>[];
    final audioReports = <String>[];
    for (final report in reports) {
      final values = report.values;
      final type = report.type;
      if (type == 'candidate-pair' && isSelectedCandidatePair(values)) {
        selectedPairs.add(candidatePairSummary(report.id, values));
      }
      if (isAudioStatsReport(type, values)) {
        audioReports.add(audioReportSummary(report.id, type, values));
      }
    }
    return WebRtcStatsSnapshotSummary(
      selected: selectedPairs.isEmpty ? 'none' : selectedPairs.join(' | '),
      audio: audioReports.isEmpty ? 'none' : audioReports.take(6).join(' | '),
    );
  }

  String candidatePairSummary(String id, Map<dynamic, dynamic> values) {
    return 'pair=$id state=${stat(values, 'state')} nominated=${stat(values, 'nominated')} local=${stat(values, 'localCandidateId')} remote=${stat(values, 'remoteCandidateId')} sent=${stat(values, 'bytesSent')} recv=${stat(values, 'bytesReceived')} rtt=${stat(values, 'currentRoundTripTime')}';
  }

  String audioReportSummary(
    String id,
    String type,
    Map<dynamic, dynamic> values,
  ) {
    return '$type id=$id kind=${stat(values, 'kind')} media=${stat(values, 'mediaType')} packetsSent=${stat(values, 'packetsSent')} packetsRecv=${stat(values, 'packetsReceived')} bytesSent=${stat(values, 'bytesSent')} bytesRecv=${stat(values, 'bytesReceived')} audioLevel=${stat(values, 'audioLevel')} totalAudioEnergy=${stat(values, 'totalAudioEnergy')}';
  }

  bool isSelectedCandidatePair(Map<dynamic, dynamic> values) {
    final selected = values['selected'];
    final nominated = values['nominated'];
    final state = values['state'];
    return selected == true || (nominated == true && state == 'succeeded');
  }

  bool isAudioStatsReport(String type, Map<dynamic, dynamic> values) {
    final kind = values['kind']?.toString();
    final mediaType = values['mediaType']?.toString();
    return kind == 'audio' ||
        mediaType == 'audio' ||
        type == 'media-source' ||
        type == 'inbound-rtp' ||
        type == 'outbound-rtp';
  }

  String stat(Map<dynamic, dynamic> values, String key) {
    final value = values[key];
    return value == null ? '-' : value.toString();
  }
}
