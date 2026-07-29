import 'package:flutter/material.dart';

abstract interface class FloatingVideoDownloadRuntime<TDownloadContext> {
  String? normalizeTitle(String? title);

  String redactUrl(String url);

  String resolveFileName(String url, {String? pageTitle});

  Future<void> startDownload({
    required BuildContext context,
    required TDownloadContext downloadContext,
    required String url,
    required void Function(String message) onStatus,
    OverlayEntry? dialogAnchorOverlay,
    String? displayUrl,
    String? suggestedFileName,
    Map<String, String>? requestHeaders,
  });
}
