class PreparedVideoPlayback {
  const PreparedVideoPlayback({
    required this.playbackUrl,
    required this.downloadUrl,
    required this.displayDownloadUrl,
    this.resolvedTitle,
    this.downloadHeaders,
  });

  final String playbackUrl;
  final String downloadUrl;
  final String displayDownloadUrl;
  final String? resolvedTitle;
  final Map<String, String>? downloadHeaders;
}

abstract class VideoPlaybackPreparer {
  Future<PreparedVideoPlayback> prepare({
    required String requestedUrl,
    required bool shouldResolveYoutube,
  });
}
