import 'dart:async';
import 'dart:io';

import '../browser_settings.dart';
import '../../features/proxy/infrastructure/proxy_service.dart';

/// A minimal local HTTP proxy-forwarding server for video streams.
///
/// VideoPlayerController connects to this local server (e.g. http://127.0.0.1:port/proxy?url=...)
/// and this server forwards the request through the app's configured proxy.
/// This allows video_player (which uses native ExoPlayer) to play URLs that
/// require proxy access.
class VideoProxyServer {
  HttpServer? _server;
  int? _boundPort;

  int? get boundPort => _boundPort;

  bool get isRunning => _server != null;

  /// Starts the local forwarding server on an available port.
  Future<void> start({
    required ProxyService proxyService,
    required BrowserSettings settings,
    int preferredPort = 0,
  }) async {
    if (_server != null) {
      return;
    }

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      preferredPort,
    );
    _server = server;
    _boundPort = server.port;

    server.listen((request) async {
      try {
        await _handleRequest(request, proxyService, settings);
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Proxy error: $e')
          ..close();
      }
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _boundPort = null;
  }

  /// Builds a local proxy URL for the given target URL.
  String buildProxyUrl(String targetUrl) {
    final port = _boundPort;
    if (port == null) {
      throw StateError('VideoProxyServer is not running');
    }
    final encoded = Uri.encodeComponent(targetUrl);
    return 'http://127.0.0.1:$port/proxy?url=$encoded';
  }

  Future<void> _handleRequest(
    HttpRequest request,
    ProxyService proxyService,
    BrowserSettings settings,
  ) async {
    if (request.uri.path != '/proxy') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found')
        ..close();
      return;
    }

    final targetUrl = request.uri.queryParameters['url'];
    if (targetUrl == null || targetUrl.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing url parameter')
        ..close();
      return;
    }

    final targetUri = Uri.parse(targetUrl);

    final client = HttpClient();
    client.findProxy = (uri) =>
        proxyService.findProxyForDownload(settings.proxyConfiguration, uri);

    try {
      final proxyRequest = await client.openUrl(request.method, targetUri);

      // Forward relevant headers
      request.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'host' || lower == 'connection') return;
        for (final value in values) {
          proxyRequest.headers.add(name, value);
        }
      });

      // Forward body if present
      await request.forEach(proxyRequest.add);
      await proxyRequest.close();

      final proxyResponse = await proxyRequest.done;

      request.response.statusCode = proxyResponse.statusCode;
      proxyResponse.headers.forEach((name, values) {
        for (final value in values) {
          request.response.headers.add(name, value);
        }
      });

      await proxyResponse.pipe(request.response);
    } finally {
      client.close(force: true);
    }
  }
}
