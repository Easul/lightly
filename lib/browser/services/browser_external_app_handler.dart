import 'package:flutter/material.dart';

typedef ExternalAppStatusLauncher = Future<String> Function(Uri requestedUrl);
typedef ExternalAppConfirmDialog =
    Future<bool> Function(BuildContext context, Uri requestedUrl);

class BrowserExternalAppHandler {
  BrowserExternalAppHandler({
    ExternalAppConfirmDialog? confirmOpenDialog,
    ExternalAppConfirmDialog? confirmBlockedDialog,
  }) : _confirmOpenDialog = confirmOpenDialog ?? _defaultConfirmOpenDialog,
       _confirmBlockedDialog =
           confirmBlockedDialog ?? _defaultConfirmBlockedDialog;

  final ExternalAppConfirmDialog _confirmOpenDialog;
  final ExternalAppConfirmDialog _confirmBlockedDialog;

  bool _isShowingExternalAppDialog = false;

  bool get isShowingExternalAppDialog => _isShowingExternalAppDialog;

  Future<String?> handleBlockedByResponse(
    BuildContext context,
    Uri? requestedUrl, {
    required bool Function(String? url) shouldSuppressPopupUrl,
    required ExternalAppStatusLauncher launchExternalUrl,
  }) async {
    if (requestedUrl == null ||
        shouldSuppressPopupUrl(requestedUrl.toString())) {
      return null;
    }
    if (_isShowingExternalAppDialog) {
      return null;
    }

    _isShowingExternalAppDialog = true;
    try {
      final shouldOpen = await _confirmBlockedDialog(context, requestedUrl);
      if (!shouldOpen) {
        return null;
      }
      return launchExternalUrl(requestedUrl);
    } finally {
      _isShowingExternalAppDialog = false;
    }
  }

  Future<String?> confirmAndLaunchExternalUrl(
    BuildContext context,
    Uri requestedUrl, {
    required ExternalAppStatusLauncher launchExternalUrl,
  }) async {
    if (_isShowingExternalAppDialog) {
      return null;
    }

    _isShowingExternalAppDialog = true;
    try {
      final confirmed = await _confirmOpenDialog(context, requestedUrl);
      if (!confirmed) {
        return null;
      }
      return launchExternalUrl(requestedUrl);
    } finally {
      _isShowingExternalAppDialog = false;
    }
  }

  static Future<bool> _defaultConfirmOpenDialog(
    BuildContext context,
    Uri requestedUrl,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开外部应用'),
        content: Text('该链接需要使用外部应用打开，是否继续？\n\n${requestedUrl.toString()}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  static Future<bool> _defaultConfirmBlockedDialog(
    BuildContext context,
    Uri requestedUrl,
  ) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳转被网页拦截'),
        content: Text('当前网页阻止了该弹窗/跳转，是否改为外部打开？\n\n${requestedUrl.toString()}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    return shouldOpen == true;
  }
}
