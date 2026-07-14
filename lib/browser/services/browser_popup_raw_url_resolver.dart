import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/app_log_service.dart';
import '../utils/browser_popup_raw_url_capture.dart';

typedef BrowserPopupJavascriptEvaluator =
    Future<dynamic> Function(String source);
typedef BrowserPopupResolutionLogWriter =
    Future<void> Function(Map<String, Object?> metadata);

class BrowserPopupRawUrlResolver {
  BrowserPopupRawUrlResolver({
    BrowserPopupResolutionLogWriter? logWriter,
    void Function(String message)? debugWriter,
    bool? debugLoggingEnabled,
  }) : _logWriter = logWriter ?? _writeAppLog,
       _debugWriter = debugWriter ?? debugPrint,
       _debugLoggingEnabled =
           debugLoggingEnabled ?? (kDebugMode || kProfileMode);

  static const int _maxCapturedUrls = 12;

  final BrowserPopupResolutionLogWriter _logWriter;
  final void Function(String message) _debugWriter;
  final bool _debugLoggingEnabled;
  final List<String> _capturedUrls = <String>[];

  void recordCapturedUrl(String rawUrl) {
    _capturedUrls.add(rawUrl);
    if (_capturedUrls.length > _maxCapturedUrls) {
      _capturedUrls.removeAt(0);
    }
  }

  Future<String> resolve({
    required String fallbackUrl,
    required BrowserPopupJavascriptEvaluator evaluateJavascript,
  }) async {
    final bridgedBefore = BrowserPopupRawUrlCapture.takeBestCapturedUrl(
      _capturedUrls,
      fallbackUrl,
    );
    if (bridgedBefore != null) {
      _logResolution(
        source: 'javascript-bridge-before-callback',
        fallbackUrl: fallbackUrl,
        resolvedUrl: bridgedBefore,
      );
      return bridgedBefore;
    }

    String? scriptCapturedUrl;
    try {
      final result = await evaluateJavascript(
        BrowserPopupRawUrlCapture.takeLatestScript(fallbackUrl),
      );
      scriptCapturedUrl = BrowserPopupRawUrlCapture.capturedUrlFromResult(
        result,
      );
    } catch (error) {
      _debugWriter('Failed to read captured popup URL: $error');
    }

    await Future<void>.delayed(Duration.zero);
    final bridgedAfter = BrowserPopupRawUrlCapture.takeBestCapturedUrl(
      _capturedUrls,
      fallbackUrl,
    );
    final resolvedUrl = bridgedAfter ?? scriptCapturedUrl ?? fallbackUrl;
    _logResolution(
      source: bridgedAfter != null
          ? 'javascript-bridge-after-callback'
          : scriptCapturedUrl != null
          ? 'main-frame-script-queue'
          : 'webview-callback-fallback',
      fallbackUrl: fallbackUrl,
      resolvedUrl: resolvedUrl,
    );
    return resolvedUrl;
  }

  void _logResolution({
    required String source,
    required String fallbackUrl,
    required String resolvedUrl,
  }) {
    if (_debugLoggingEnabled) {
      _debugWriter(
        '[PopupUrlResolution] source=$source '
        'fallbackLength=${fallbackUrl.length} '
        'resolvedLength=${resolvedUrl.length} '
        'fallbackCamel=${fallbackUrl.contains('jumpToSharedProduct')} '
        'fallbackLower=${fallbackUrl.contains('jumptosharedproduct')} '
        'resolvedCamel=${resolvedUrl.contains('jumpToSharedProduct')} '
        'resolvedLower=${resolvedUrl.contains('jumptosharedproduct')} '
        'resolvedTrafficTag=${resolvedUrl.contains('trafficTag')}',
      );
    }
    unawaited(
      _logWriter(<String, Object?>{
        'source': source,
        'fallbackLength': fallbackUrl.length,
        'resolvedLength': resolvedUrl.length,
        'fallbackHasCamelMethod': fallbackUrl.contains('jumpToSharedProduct'),
        'fallbackHasLowerMethod': fallbackUrl.contains('jumptosharedproduct'),
        'resolvedHasCamelMethod': resolvedUrl.contains('jumpToSharedProduct'),
        'resolvedHasLowerMethod': resolvedUrl.contains('jumptosharedproduct'),
        'fallbackHasCamelTrafficTag': fallbackUrl.contains('trafficTag'),
        'resolvedHasCamelTrafficTag': resolvedUrl.contains('trafficTag'),
      }),
    );
  }

  static Future<void> _writeAppLog(Map<String, Object?> metadata) {
    return AppLogService.instance.log(
      'Browser popup URL resolved',
      metadata: metadata,
    );
  }
}
