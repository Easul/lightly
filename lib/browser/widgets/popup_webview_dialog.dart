import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/browser_auth_dialog_service.dart';
import '../services/browser_external_url_launcher_service.dart';
import '../utils/browser_auth_url_detector.dart';
import '../utils/browser_popup_filter.dart';
import '../utils/ui_update_thresholds.dart';

class PopupWebViewDialog extends StatefulWidget {
  const PopupWebViewDialog({this.windowId, required this.initialUrl});

  final int? windowId;
  final String? initialUrl;

  @override
  State<PopupWebViewDialog> createState() => _PopupWebViewDialogState();
}

class _PopupWebViewDialogState extends State<PopupWebViewDialog> {
  InAppWebViewController? _controller;
  final BrowserExternalUrlLauncherService _externalUrlLauncher =
      BrowserExternalUrlLauncherService();
  String _title = '登录窗口';
  String? _currentUrl;
  int _progress = 0;

  static final InAppWebViewSettings _popupSettings = InAppWebViewSettings(
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    useShouldOverrideUrlLoading: true,
    supportMultipleWindows: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    thirdPartyCookiesEnabled: true,
    allowFileAccess: true,
    allowContentAccess: true,
  );

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
  }

  void _closeDialog() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _updateTitleIfNeeded(String? title) {
    final nextTitle = (title == null || title.trim().isEmpty) ? '登录窗口' : title;
    if (!mounted || _title == nextTitle) return;
    setState(() => _title = nextTitle);
  }

  void _updatePopupState({String? currentUrl, int? progress}) {
    final nextUrl = currentUrl ?? _currentUrl;
    final nextProgress = progress ?? _progress;
    if (!mounted || (_currentUrl == nextUrl && _progress == nextProgress))
      return;
    setState(() {
      _currentUrl = nextUrl;
      _progress = nextProgress;
    });
  }

  void _updateProgressIfNeeded(int progress) {
    if (!shouldUpdateWebProgress(_progress, progress)) return;
    _updatePopupState(progress: progress);
  }

  bool _isWebScheme(String? scheme) {
    return BrowserPopupFilter.isWebScheme(scheme);
  }

  bool _isTrustedAuthPopup(String popupUrl) {
    return BrowserAuthUrlDetector.isTrustedAuthPopupUrl(popupUrl);
  }

  bool _looksLikeAuthUrl(String? url) {
    return BrowserAuthUrlDetector.looksLikeAuthUrl(url);
  }

  bool _shouldAllowDeferredAuthPopup(CreateWindowAction createWindowAction) {
    return BrowserAuthUrlDetector.shouldAllowDeferredAuthPopup(
      createWindowAction,
      currentUrl: _currentUrl,
    );
  }

  Future<HttpAuthResponse?> _handleHttpAuthRequest(
    InAppWebViewController controller,
    URLAuthenticationChallenge challenge,
  ) async {
    if (!mounted) {
      return HttpAuthResponse(action: HttpAuthResponseAction.CANCEL);
    }
    return BrowserAuthDialogService.showAuthDialog(context, challenge);
  }

  bool _shouldSuppressPopupUrl(String? popupUrl) {
    return BrowserPopupFilter.shouldSuppressPopupUrl(popupUrl);
  }

  Future<NavigationActionPolicy> _handleShouldOverrideUrlLoading(
    NavigationAction navigationAction,
  ) async {
    final requestedUrl = navigationAction.request.url;
    if (requestedUrl == null || _isWebScheme(requestedUrl.scheme)) {
      return NavigationActionPolicy.ALLOW;
    }

    _updateTitleIfNeeded(await _externalUrlLauncher.launch(requestedUrl));
    return NavigationActionPolicy.CANCEL;
  }

  Future<void> _handleReceivedError(
    WebResourceRequest request,
    WebResourceError error,
  ) async {
    final requestedUrl = request.url;
    final description = error.description;

    if (!_isWebScheme(requestedUrl.scheme)) {
      if (description.contains('ERR_UNKNOWN_URL_SCHEME') ||
          description.contains('ERR_BLOCKED_BY_RESPONSE')) {
        _updateTitleIfNeeded(await _externalUrlLauncher.launch(requestedUrl));
        return;
      }
    }

    _updateTitleIfNeeded(description);
  }

  void _handleVisitedHistoryUpdate(Uri? requestedUrl) {
    if (requestedUrl == null) {
      return;
    }

    if (_isWebScheme(requestedUrl.scheme)) {
      _updatePopupState(currentUrl: requestedUrl.toString());
      return;
    }

    unawaited(
      _externalUrlLauncher.launch(requestedUrl).then(_updateTitleIfNeeded),
    );
  }

  Future<bool> _confirmPopupNavigation(String popupUrl) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开弹窗'),
        content: Text('网页请求打开一个新窗口，是否继续？\n\n$popupUrl'),
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

  Future<bool> _showNestedPopupWindow({
    required int? windowId,
    String? initialUrl,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          PopupWebViewDialog(windowId: windowId, initialUrl: initialUrl),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _closeDialog,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_currentUrl != null)
                          Text(
                            _currentUrl!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(
              value: _progress > 0 ? _progress / 100 : 0,
              minHeight: 2,
            ),
            Expanded(
              child: InAppWebView(
                windowId: widget.windowId,
                initialUrlRequest:
                    widget.windowId == null &&
                        (widget.initialUrl?.isNotEmpty ?? false)
                    ? URLRequest(url: WebUri(widget.initialUrl!))
                    : null,
                initialSettings: _popupSettings,
                onWebViewCreated: (controller) => _controller = controller,
                shouldOverrideUrlLoading: (_, navigationAction) =>
                    _handleShouldOverrideUrlLoading(navigationAction),
                onCloseWindow: (_) => _closeDialog(),
                onTitleChanged: (_, title) => _updateTitleIfNeeded(title),
                onLoadStart: (_, url) =>
                    _updatePopupState(currentUrl: url?.toString(), progress: 0),
                onLoadStop: (_, url) => _updatePopupState(
                  currentUrl: url?.toString(),
                  progress: 100,
                ),
                onUpdateVisitedHistory: (_, url, isReload) =>
                    _handleVisitedHistoryUpdate(url),
                onProgressChanged: (_, progress) =>
                    _updateProgressIfNeeded(progress),
                onReceivedError: (_, request, error) =>
                    _handleReceivedError(request, error),
                onReceivedHttpAuthRequest: _handleHttpAuthRequest,
                onCreateWindow: (controller, createWindowAction) async {
                  final popupUrl = createWindowAction.request.url?.toString();
                  if ((popupUrl == null || popupUrl.isEmpty) &&
                      _shouldAllowDeferredAuthPopup(createWindowAction)) {
                    return _showNestedPopupWindow(
                      windowId: createWindowAction.windowId,
                    );
                  }
                  if (_shouldSuppressPopupUrl(popupUrl)) {
                    return false;
                  }
                  if (popupUrl != null && popupUrl.isNotEmpty) {
                    final shouldOpen = _isTrustedAuthPopup(popupUrl)
                        ? true
                        : await _confirmPopupNavigation(popupUrl);
                    if (!shouldOpen) {
                      return false;
                    }
                    final uri = Uri.tryParse(popupUrl);
                    final scheme = uri?.scheme.toLowerCase();
                    if (scheme != null &&
                        scheme.isNotEmpty &&
                        scheme != 'http' &&
                        scheme != 'https' &&
                        scheme != 'file' &&
                        scheme != 'content') {
                      await _externalUrlLauncher.launch(uri!);
                      return false;
                    }
                    return _showNestedPopupWindow(
                      windowId: createWindowAction.windowId,
                      initialUrl: popupUrl,
                    );
                  }
                  return false;
                },
                onPermissionRequest: (controller, permissionRequest) async {
                  return PermissionResponse(
                    resources: permissionRequest.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
