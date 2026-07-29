import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A minimal local HTTP proxy-forwarding server for video streams.
///
/// VideoPlayerController connects to this local server (e.g. http://127.0.0.1:port/proxy?url=...)
/// and this server forwards the request through the injected proxy route.
/// This allows video_player (which uses native ExoPlayer) to play URLs that
/// require proxy access.
class VideoProxyServer {
  VideoProxyServer({
    List<String> allowedHostSuffixes = const <String>['googlevideo.com'],
  }) : _allowedHostSuffixes = allowedHostSuffixes
           .map(
             (value) =>
                 value.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), ''),
           )
           .where((value) => value.isNotEmpty)
           .toList(growable: false);

  static const int _maxHeaderContexts = 32;
  static const Set<String> _injectedHeaderAllowlist = <String>{
    HttpHeaders.authorizationHeader,
    HttpHeaders.cookieHeader,
    'origin',
    HttpHeaders.refererHeader,
    HttpHeaders.userAgentHeader,
  };
  static const Set<String> _blockedInboundHeaders = <String>{
    HttpHeaders.authorizationHeader,
    HttpHeaders.connectionHeader,
    HttpHeaders.contentLengthHeader,
    HttpHeaders.cookieHeader,
    HttpHeaders.hostHeader,
    'origin',
    HttpHeaders.proxyAuthorizationHeader,
    HttpHeaders.refererHeader,
    HttpHeaders.transferEncodingHeader,
  };

  final List<String> _allowedHostSuffixes;
  final LinkedHashMap<String, _VideoProxyHeaderContext> _headerContexts =
      LinkedHashMap<String, _VideoProxyHeaderContext>();
  final Random _random = Random.secure();
  HttpServer? _server;
  int? _boundPort;

  int? get boundPort => _boundPort;

  bool get isRunning => _server != null;

  /// Starts the local forwarding server on an available port.
  Future<void> start({
    required String Function(Uri uri) proxyResolver,
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
        await _handleRequest(request, proxyResolver);
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Proxy error')
          ..close();
      }
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _boundPort = null;
    _headerContexts.clear();
  }

  /// Builds a local proxy URL for the given target URL.
  String buildProxyUrl(String targetUrl, {Map<String, String>? headers}) {
    final port = _boundPort;
    if (port == null) {
      throw StateError('VideoProxyServer is not running');
    }
    final encoded = Uri.encodeComponent(targetUrl);
    final proxyUrl = StringBuffer('http://127.0.0.1:$port/proxy?url=$encoded');
    final sanitizedHeaders = _sanitizeInjectedHeaders(headers);
    if (sanitizedHeaders.isNotEmpty) {
      final token = _createHeaderContext(targetUrl, sanitizedHeaders);
      proxyUrl.write('&context=${Uri.encodeComponent(token)}');
    }
    return proxyUrl.toString();
  }

  Future<void> _handleRequest(
    HttpRequest request,
    String Function(Uri uri) proxyResolver,
  ) async {
    if (request.uri.path != '/proxy') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found')
        ..close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write('Method not allowed')
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

    final targetUri = Uri.tryParse(targetUrl);
    if (targetUri == null ||
        !_isHttpUrl(targetUri) ||
        targetUri.userInfo.isNotEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid url parameter')
        ..close();
      return;
    }
    if (!_isAllowedHost(targetUri.host)) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('Host not allowed')
        ..close();
      return;
    }

    final contextToken = request.uri.queryParameters['context'];
    final headerContext = contextToken == null
        ? null
        : _headerContexts[contextToken];
    if (contextToken != null &&
        (headerContext == null || headerContext.targetUrl != targetUrl)) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('Invalid request context')
        ..close();
      return;
    }

    final client = HttpClient();
    client.findProxy = proxyResolver;

    try {
      final proxyRequest = await client.openUrl(request.method, targetUri);
      proxyRequest.followRedirects = false;

      final injectedHeaders =
          headerContext?.headers ?? const <String, String>{};
      final injectedNames = injectedHeaders.keys.toSet();
      request.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (_blockedInboundHeaders.contains(lower) ||
            injectedNames.contains(lower)) {
          return;
        }
        for (final value in values) {
          proxyRequest.headers.add(name, value);
        }
      });
      injectedHeaders.forEach(proxyRequest.headers.set);

      final proxyResponse = await proxyRequest.close();

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

  Map<String, String> _sanitizeInjectedHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{
      for (final entry in headers.entries)
        if (_injectedHeaderAllowlist.contains(entry.key.toLowerCase()) &&
            entry.value.trim().isNotEmpty)
          entry.key.toLowerCase(): entry.value.trim(),
    };
  }

  String _createHeaderContext(String targetUrl, Map<String, String> headers) {
    while (_headerContexts.length >= _maxHeaderContexts) {
      _headerContexts.remove(_headerContexts.keys.first);
    }
    final token = base64Url
        .encode(List<int>.generate(18, (_) => _random.nextInt(256)))
        .replaceAll('=', '');
    _headerContexts[token] = _VideoProxyHeaderContext(
      targetUrl: targetUrl,
      headers: Map<String, String>.unmodifiable(headers),
    );
    return token;
  }

  bool _isHttpUrl(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
  }

  bool _isAllowedHost(String host) {
    final normalizedHost = host.toLowerCase();
    return _allowedHostSuffixes.any(
      (rule) => normalizedHost == rule || normalizedHost.endsWith('.$rule'),
    );
  }
}

class _VideoProxyHeaderContext {
  const _VideoProxyHeaderContext({
    required this.targetUrl,
    required this.headers,
  });

  final String targetUrl;
  final Map<String, String> headers;
}
