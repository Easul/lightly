import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../features/video/domain/youtube_long_press_utils.dart';
import '../widgets/browser_long_press_actions_sheet.dart';

class BrowserLongPressRequest {
  const BrowserLongPressRequest._({
    required this.url,
    required this.isImage,
    this.youtubeTargets,
  });

  factory BrowserLongPressRequest.standard({
    required String url,
    required bool isImage,
  }) {
    return BrowserLongPressRequest._(url: url, isImage: isImage);
  }

  factory BrowserLongPressRequest.youtube({
    required String url,
    required YouTubeLongPressTargets youtubeTargets,
  }) {
    return BrowserLongPressRequest._(
      url: url,
      isImage: false,
      youtubeTargets: youtubeTargets,
    );
  }

  final String url;
  final bool isImage;
  final YouTubeLongPressTargets? youtubeTargets;

  bool get isYouTube => youtubeTargets != null;
  LongPressActionType get actionType =>
      isImage ? LongPressActionType.image : LongPressActionType.link;
}

class BrowserLongPressHandler {
  bool _isShowingDialog = false;

  bool get isShowingDialog => _isShowingDialog;

  BrowserLongPressRequest? createRequest({
    required String? url,
    required InAppWebViewHitTestResultType type,
  }) {
    if (_isShowingDialog || url == null || url.isEmpty) {
      return null;
    }

    final isImage =
        type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE ||
        type == InAppWebViewHitTestResultType.IMAGE_TYPE;
    final isLink =
        type == InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE ||
        type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE;

    if (!isImage && !isLink) {
      return null;
    }

    final youtubeTargets = deriveYouTubeLongPressTargets(url);
    if (youtubeTargets != null) {
      return BrowserLongPressRequest.youtube(
        url: url,
        youtubeTargets: youtubeTargets,
      );
    }

    return BrowserLongPressRequest.standard(url: url, isImage: isImage);
  }

  Future<void> showActions({
    required BuildContext context,
    required BrowserLongPressRequest request,
    required bool nativeVideoPlayerEnabled,
    required Future<void> Function(String url) onOpenInNewTab,
    required Future<void> Function(String text) onCopyToClipboard,
    required Future<void> Function(String url) onDownload,
    required Future<void> Function(String url) onOpenOriginalVideo,
    required void Function(String message) onStatus,
  }) async {
    if (_isShowingDialog) {
      return;
    }

    _isShowingDialog = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) {
          if (request.isYouTube) {
            final youtubeTargets = request.youtubeTargets!;
            return BrowserYouTubeLongPressActionsSheet(
              videoUrl: youtubeTargets.mobileWatchUrl,
              thumbnailUrl: youtubeTargets.thumbnailUrl,
              originalVideoUrl: youtubeTargets.desktopWatchUrl,
              onOpenVideo: () async {
                await onOpenInNewTab(youtubeTargets.mobileWatchUrl);
              },
              onCopyVideo: () async {
                await onCopyToClipboard(youtubeTargets.mobileWatchUrl);
                onStatus('已复制视频链接');
              },
              onOpenThumbnail: () async {
                await onOpenInNewTab(youtubeTargets.thumbnailUrl);
              },
              onCopyThumbnail: () async {
                await onCopyToClipboard(youtubeTargets.thumbnailUrl);
                onStatus('已复制封面图链接');
              },
              onOpenOriginalVideo: () async {
                if (!nativeVideoPlayerEnabled) {
                  await onOpenInNewTab(youtubeTargets.desktopWatchUrl);
                  return;
                }
                await onOpenOriginalVideo(youtubeTargets.desktopWatchUrl);
              },
            );
          }

          return BrowserLongPressActionsSheet(
            type: request.actionType,
            url: request.url,
            onOpenInNewTab: () async {
              await onOpenInNewTab(request.url);
            },
            onCopyLink: () async {
              await onCopyToClipboard(request.url);
              onStatus('已复制到剪贴板');
            },
            onDownload: () async {
              await onDownload(request.url);
            },
          );
        },
      );
    } finally {
      _isShowingDialog = false;
    }
  }

  Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
