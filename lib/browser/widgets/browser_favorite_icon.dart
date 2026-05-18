import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../browser_settings.dart';
import '../proxy_service.dart';

class BrowserFavoriteIcon extends StatefulWidget {
  const BrowserFavoriteIcon({
    super.key,
    required this.url,
    required this.title,
    required this.settings,
    required this.proxyService,
    this.size = 44,
    this.onTap,
    this.onLongPress,
  });

  final String url;
  final String title;
  final BrowserSettings settings;
  final ProxyService proxyService;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<BrowserFavoriteIcon> createState() => _BrowserFavoriteIconState();
}

class _BrowserFavoriteIconState extends State<BrowserFavoriteIcon> {
  static final Map<String, Future<Uint8List?>> _iconFutureCache =
      <String, Future<Uint8List?>>{};

  late Future<Uint8List?> _iconBytesFuture;

  @override
  void initState() {
    super.initState();
    _iconBytesFuture = _resolveIconBytes();
  }

  @override
  void didUpdateWidget(covariant BrowserFavoriteIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.settings.shouldApplyProxy !=
            widget.settings.shouldApplyProxy) {
      _iconBytesFuture = _resolveIconBytes();
    }
  }

  Future<Uint8List?> _resolveIconBytes() {
    final cacheKey = '${widget.url}::${widget.settings.shouldApplyProxy}';
    return _iconFutureCache.putIfAbsent(cacheKey, _fetchIconBytes);
  }

  Future<Uint8List?> _fetchIconBytes() async {
    final pageUri = Uri.tryParse(widget.url);
    if (pageUri == null || pageUri.host.isEmpty) {
      return null;
    }

    final candidateUris = <Uri>[
      pageUri.resolve('/favicon.ico'),
      Uri.https('www.google.com', '/s2/favicons', {
        'domain': pageUri.host,
        'sz': '64',
      }),
    ];

    for (final candidate in candidateUris) {
      final bytes = await _downloadIconBytes(candidate, refererUri: pageUri);
      if (bytes != null && bytes.isNotEmpty) {
        return bytes;
      }
    }

    return null;
  }

  Future<Uint8List?> _downloadIconBytes(
    Uri iconUri, {
    required Uri refererUri,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    if (widget.settings.shouldApplyProxy) {
      client.findProxy = (uri) =>
          widget.proxyService.findProxyForDownload(widget.settings, uri);
    }

    try {
      final request = await client.getUrl(iconUri);
      if (iconUri.host != 'www.google.com') {
        request.headers.set(
          HttpHeaders.refererHeader,
          '${refererUri.scheme}://${refererUri.host}',
        );
      }
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      return consolidateHttpClientResponseBytes(response);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Color get _fallbackColor {
    final hash = widget.url.hashCode.abs();
    final colors = [
      const Color(0xFF63B746),
      const Color(0xFF7BCB7A),
      const Color(0xFF8ABF94),
      const Color(0xFF6FAA8F),
      const Color(0xFF79B6A8),
      const Color(0xFF9BBE73),
    ];
    return colors[hash % colors.length];
  }

  String get _initial {
    final trimmed = widget.title.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = Container(
      color: _fallbackColor,
      child: Center(
        child: Text(
          _initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: widget.size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(widget.size * 0.34),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.size * 0.34),
              child: FutureBuilder<Uint8List?>(
                future: _iconBytesFuture,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null || bytes.isEmpty) {
                    return fallback;
                  }
                  return Image.memory(
                    bytes,
                    width: widget.size,
                    height: widget.size,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (context, error, stackTrace) => fallback,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: widget.size + 16,
            child: Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurface,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
