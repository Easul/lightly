import 'package:flutter/material.dart';

import '../../features/video/presentation/floating_video_download_runtime.dart';
import '../browser_settings.dart';
import 'browser_download_coordinator.dart';

class BrowserFloatingVideoDownloadRuntime
    implements FloatingVideoDownloadRuntime<BrowserSettings> {
  const BrowserFloatingVideoDownloadRuntime({
    required BrowserDownloadCoordinator downloadCoordinator,
  }) : _downloadCoordinator = downloadCoordinator;

  final BrowserDownloadCoordinator _downloadCoordinator;

  @override
  String? normalizeTitle(String? title) {
    final trimmed = title?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return BrowserDownloadCoordinator.normalizeFloatingDownloadTitle(trimmed);
  }

  @override
  String redactUrl(String url) =>
      BrowserDownloadCoordinator.redactDownloadUrl(url);

  @override
  String resolveFileName(String url, {String? pageTitle}) {
    return _downloadCoordinator.resolveFloatingDownloadFileName(
      url,
      pageTitle: pageTitle,
    );
  }

  @override
  Future<void> startDownload({
    required BuildContext context,
    required BrowserSettings downloadContext,
    required String url,
    required void Function(String message) onStatus,
    OverlayEntry? dialogAnchorOverlay,
    String? displayUrl,
    String? suggestedFileName,
    Map<String, String>? requestHeaders,
  }) {
    return _downloadCoordinator.startDownloadFromUrl(
      context: context,
      url: url,
      settings: downloadContext,
      onStatus: onStatus,
      dialogAnchorOverlay: dialogAnchorOverlay,
      displayUrl: displayUrl,
      suggestedFileName: suggestedFileName,
      overrideHeaders: requestHeaders,
    );
  }
}
