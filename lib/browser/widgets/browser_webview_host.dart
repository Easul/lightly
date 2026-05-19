import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const _browserMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
const _browserDesktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class BrowserWebViewHost extends StatelessWidget {
  const BrowserWebViewHost({
    super.key,
    required this.enabled,
    required this.initialUrl,
    this.windowId,
    this.keepAlive,
    required this.isLoading,
    required this.progressListenable,
    required this.onWebViewCreated,
    required this.shouldOverrideUrlLoading,
    required this.onCreateWindow,
    required this.onDownloadStartRequest,
    required this.onLoadStart,
    required this.onLoadStop,
    required this.onProgressChanged,
    required this.onReceivedError,
    required this.onReceivedHttpAuthRequest,
    required this.onScrollChanged,
    required this.onTitleChanged,
    required this.onUpdateVisitedHistory,
    this.onLongPressHitTestResult,
    this.onEnterFullscreen,
    this.onExitFullscreen,
    this.pullToRefreshController,
    this.findInteractionController,
  });

  final bool enabled;
  final String initialUrl;
  final int? windowId;
  final InAppWebViewKeepAlive? keepAlive;
  final bool isLoading;
  final ValueListenable<int> progressListenable;
  final void Function(InAppWebViewController controller) onWebViewCreated;
  final Future<NavigationActionPolicy?> Function(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  )
  shouldOverrideUrlLoading;
  final Future<bool?> Function(
    InAppWebViewController controller,
    CreateWindowAction createWindowAction,
  )
  onCreateWindow;
  final Future<void> Function(
    InAppWebViewController controller,
    DownloadStartRequest downloadStartRequest,
  )
  onDownloadStartRequest;
  final void Function(InAppWebViewController controller, WebUri? url)
  onLoadStart;
  final Future<void> Function(InAppWebViewController controller, WebUri? url)
  onLoadStop;
  final void Function(InAppWebViewController controller, int progress)
  onProgressChanged;
  final void Function(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  )
  onReceivedError;
  final Future<HttpAuthResponse?> Function(
    InAppWebViewController controller,
    URLAuthenticationChallenge challenge,
  )
  onReceivedHttpAuthRequest;
  final void Function(InAppWebViewController controller, int x, int y)
  onScrollChanged;
  final void Function(InAppWebViewController controller, String? title)
  onTitleChanged;
  final void Function(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  )
  onUpdateVisitedHistory;
  final void Function(
    InAppWebViewController controller,
    InAppWebViewHitTestResult hitTestResult,
  )?
  onLongPressHitTestResult;
  final void Function(InAppWebViewController controller)? onEnterFullscreen;
  final void Function(InAppWebViewController controller)? onExitFullscreen;
  final PullToRefreshController? pullToRefreshController;
  final FindInteractionController? findInteractionController;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initialUri = Uri.tryParse(initialUrl);
    final host = initialUri?.host.toLowerCase() ?? '';
    final prefersDesktopUserAgent =
        host == 'x.com' ||
        host.endsWith('.x.com') ||
        host.endsWith('twitter.com');

    if (!enabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.block_outlined,
                size: 64,
                color: colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'WebView 未启用',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请检查网络连接或应用配置',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        RepaintBoundary(
          child: InAppWebView(
            windowId: windowId,
            initialUrlRequest: windowId == null
                ? URLRequest(url: WebUri(initialUrl))
                : null,
            keepAlive: keepAlive,
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              javaScriptCanOpenWindowsAutomatically: true,
              useShouldOverrideUrlLoading: true,
              mediaPlaybackRequiresUserGesture: false,
              supportMultipleWindows: true,
              cacheEnabled: true,
              cacheMode: CacheMode.LOAD_DEFAULT,
              domStorageEnabled: true,
              databaseEnabled: true,
              thirdPartyCookiesEnabled: true,
              allowFileAccess: true,
              allowContentAccess: true,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              loadsImagesAutomatically: true,
              hardwareAcceleration: true,
              useHybridComposition: true,
              supportZoom: true,
              builtInZoomControls: true,
              displayZoomControls: false,
              verticalScrollBarEnabled: false,
              horizontalScrollBarEnabled: false,
              scrollbarFadingEnabled: false,
              allowsBackForwardNavigationGestures: true,
              allowsInlineMediaPlayback: true,
              userAgent: prefersDesktopUserAgent
                  ? _browserDesktopUserAgent
                  : _browserMobileUserAgent,
              isFindInteractionEnabled: true,
            ),
            onPermissionRequest: (controller, permissionRequest) async {
              return PermissionResponse(
                resources: permissionRequest.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
            onReceivedHttpAuthRequest: onReceivedHttpAuthRequest,
            onJsAlert: (controller, request) async {
              // Show native alert dialog instead of blocking
              return null;
            },
            onJsConfirm: (controller, request) async {
              // Show native confirm dialog instead of blocking
              return null;
            },
            onJsPrompt: (controller, request) async {
              // Show native prompt dialog instead of blocking
              return null;
            },
            onWebViewCreated: onWebViewCreated,
            shouldOverrideUrlLoading: shouldOverrideUrlLoading,
            onCreateWindow: onCreateWindow,
            onDownloadStartRequest: onDownloadStartRequest,
            onLoadStart: onLoadStart,
            onLoadStop: onLoadStop,
            onProgressChanged: onProgressChanged,
            onReceivedError: onReceivedError,
            onScrollChanged: onScrollChanged,
            onTitleChanged: onTitleChanged,
            onUpdateVisitedHistory: onUpdateVisitedHistory,
            onLongPressHitTestResult: onLongPressHitTestResult,
            onEnterFullscreen: onEnterFullscreen,
            onExitFullscreen: onExitFullscreen,
            onRenderProcessGone: (controller, detail) {
              // WebView renderer crashed — reload the page to recover.
              // Without this handler, a crash on heavy pages (YouTube) can
              // leave the WebView in a dead state that causes ANR.
              if (detail.didCrash) {
                unawaited(controller.reload());
              }
            },
            pullToRefreshController: pullToRefreshController,
            findInteractionController: findInteractionController,
          ),
        ),
        ValueListenableBuilder<int>(
          valueListenable: progressListenable,
          builder: (context, progress, child) {
            if (!isLoading || progress >= 100) {
              return const SizedBox.shrink();
            }

            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: progress > 0 ? progress / 100 : null,
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            );
          },
        ),
      ],
    );
  }
}
