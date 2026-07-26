class PreparedVideoPlayback {
  const PreparedVideoPlayback({
    required this.playbackUrl,
    required this.downloadUrl,
    required this.displayDownloadUrl,
    this.resolvedTitle,
  });

  final String playbackUrl;
  final String downloadUrl;
  final String displayDownloadUrl;
  final String? resolvedTitle;
}

abstract class VideoPlaybackPreparer {
  Future<PreparedVideoPlayback> prepare({
    required String requestedUrl,
    required bool shouldResolveYoutube,
  });
}
