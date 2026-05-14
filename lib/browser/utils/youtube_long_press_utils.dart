class YouTubeLongPressTargets {
  const YouTubeLongPressTargets({
    required this.videoId,
    required this.mobileWatchUrl,
    required this.desktopWatchUrl,
    required this.thumbnailUrl,
  });

  final String videoId;
  final String mobileWatchUrl;
  final String desktopWatchUrl;
  final String thumbnailUrl;
}

YouTubeLongPressTargets? deriveYouTubeLongPressTargets(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) {
    return null;
  }

  final videoId = _extractYouTubeVideoId(uri);
  if (videoId == null || videoId.isEmpty) {
    return null;
  }

  return YouTubeLongPressTargets(
    videoId: videoId,
    mobileWatchUrl: 'https://m.youtube.com/watch?v=$videoId',
    desktopWatchUrl: 'https://www.youtube.com/watch?v=$videoId',
    thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
  );
}

String? _extractYouTubeVideoId(Uri uri) {
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();

  if (host == 'youtu.be' && segments.isNotEmpty) {
    return segments.first;
  }

  if (host == 'youtube.com' ||
      host == 'www.youtube.com' ||
      host == 'm.youtube.com') {
    if (uri.path == '/watch') {
      final videoId = uri.queryParameters['v']?.trim();
      if (videoId != null && videoId.isNotEmpty) {
        return videoId;
      }
    }

    if (segments.length >= 2 &&
        (segments.first == 'shorts' || segments.first == 'embed')) {
      return segments[1];
    }
  }

  final isYtImgHost =
      host == 'i.ytimg.com' ||
      host == 'img.youtube.com' ||
      RegExp(r'^i\d+\.ytimg\.com$').hasMatch(host);

  if (isYtImgHost &&
      segments.length >= 2 &&
      (segments.first == 'vi' ||
          segments.first == 'vi_webp' ||
          segments.first == 'an_webp')) {
    return segments[1];
  }

  return null;
}
