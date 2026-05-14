import 'dart:convert';
import 'dart:io';

import 'package:http/io_client.dart';

import '../browser_settings.dart';
import '../proxy_service.dart';
import '../utils/youtube_long_press_utils.dart';
import 'video_source_resolver.dart';

/// Resolves YouTube video URLs via an external API endpoint.
///
/// HTTP requests are routed through the app's current proxy configuration
/// so the API remains reachable even when direct access is blocked.
class ExternalApiVideoSourceResolver extends VideoSourceResolver {
  ExternalApiVideoSourceResolver({
    required this.apiBaseUrl,
    required this.proxyService,
    required this.settings,
  });

  final String apiBaseUrl;
  final ProxyService proxyService;
  final BrowserSettings settings;

  @override
  Future<ResolvedVideoSource> resolve(String url) async {
    final targets = deriveYouTubeLongPressTargets(url);
    final videoId = targets?.videoId;
    if (videoId == null || videoId.isEmpty) {
      throw const VideoResolutionException('Unsupported video URL');
    }

    final httpClient = HttpClient();
    if (settings.shouldApplyProxy) {
      httpClient.findProxy = (uri) =>
          proxyService.findProxyForDownload(settings, uri);
    }

    final client = IOClient(httpClient);
    try {
      final response = await client.post(
        Uri.parse('$apiBaseUrl/parse'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': url}),
      );

      if (response.statusCode != 200) {
        throw VideoResolutionException(
          'API error ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final urls = data['urls'] as List<dynamic>?;
      if (urls == null || urls.isEmpty) {
        throw const VideoResolutionException('No playable URLs returned');
      }

      return ResolvedVideoSource(
        videoId: videoId,
        title: videoId,
        streamUrl: urls.first as String,
      );
    } finally {
      client.close();
    }
  }
}
