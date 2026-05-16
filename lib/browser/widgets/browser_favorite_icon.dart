import 'dart:io';

import 'package:flutter/material.dart';

class BrowserFavoriteIcon extends StatelessWidget {
  const BrowserFavoriteIcon({
    super.key,
    required this.url,
    required this.title,
    this.size = 44,
    this.onTap,
    this.onLongPress,
    this.proxyUrl,
  });

  final String url;
  final String title;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? proxyUrl;

  String get _faviconUrl {
    try {
      final uri = Uri.parse(url);
      return 'https://www.google.com/s2/favicons?domain=${uri.host}&sz=64';
    } catch (_) {
      return '';
    }
  }

  Map<String, String>? get _imageHeaders {
    // 当使用代理时，添加Referer头避免部分网站阻止直接请求图标
    if (proxyUrl != null && proxyUrl!.isNotEmpty) {
      try {
        final uri = Uri.parse(url);
        return {HttpHeaders.refererHeader: '${uri.scheme}://${uri.host}'};
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Color get _fallbackColor {
    final hash = url.hashCode.abs();
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
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(size * 0.34),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.34),
              child: Image.network(
                _faviconUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                headers: _imageHeaders,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: _fallbackColor,
                    child: Center(
                      child: Text(
                        _initial,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: size * 0.4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) {
                    return child;
                  }
                  return Container(
                    color: _fallbackColor,
                    child: Center(
                      child: Text(
                        _initial,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: size * 0.4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: size + 16,
            child: Text(
              title,
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
