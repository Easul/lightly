import 'dart:convert';
import 'dart:io';

import 'package:http/io_client.dart';

import '../browser_settings.dart';
import '../../features/proxy/infrastructure/proxy_service.dart';
import '../utils/youtube_long_press_utils.dart';
import '../../features/video/domain/video_source_resolver.dart';

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
          proxyService.findProxyForDownload(settings.proxyConfiguration, uri);
    }

    final client = IOClient(httpClient);
    try {
      final response = await client.post(
        _parseEndpointUri(),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': url}),
      );

      if (response.statusCode != 200) {
        throw VideoResolutionException(
          'API error ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(response.body);
      final streamUrl = _extractFirstPlayableUrl(data);
      if (streamUrl == null || streamUrl.isEmpty) {
        throw VideoResolutionException(
          'No playable URLs returned: ${response.body}',
        );
      }

      final resolvedTitle = _extractTitle(data) ?? videoId;

      return ResolvedVideoSource(
        videoId: videoId,
        title: resolvedTitle,
        streamUrl: streamUrl,
      );
    } finally {
      client.close();
    }
  }

  Uri _parseEndpointUri() {
    final baseUri = Uri.parse(apiBaseUrl.trim());
    var path = baseUri.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path == '/') {
      path = '';
    }
    if (path != '/parse' && !path.endsWith('/parse')) {
      path = '$path/parse';
    }
    return baseUri.replace(path: path, fragment: null);
  }

  String? _extractFirstPlayableUrl(dynamic data) {
    if (data is List) {
      for (final item in data) {
        final candidate = _extractFirstPlayableUrl(item);
        if (candidate != null && candidate.isNotEmpty) {
          return candidate;
        }
      }
      return null;
    }

    if (data is String) {
      return data.isNotEmpty ? data : null;
    }

    if (data is! Map<String, dynamic>) {
      return null;
    }

    final directUrl = data['url'];
    if (directUrl is String && directUrl.isNotEmpty) {
      return directUrl;
    }

    final directUrls = data['urls'];
    if (directUrls is List) {
      for (final item in directUrls) {
        if (item is String && item.isNotEmpty) {
          return item;
        }
      }
    }

    for (final key in const ['data', 'result']) {
      final nested = _extractFirstPlayableUrl(data[key]);
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }
    }

    return null;
  }

  String? _extractTitle(dynamic data) {
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final title = data['title'];
    if (title is String && title.trim().isNotEmpty) {
      return title.trim();
    }

    for (final key in const ['data', 'result']) {
      final nested = _extractTitle(data[key]);
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }
    }

    return null;
  }
}
