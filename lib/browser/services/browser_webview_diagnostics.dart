import 'dart:async';

import '../../services/app_log_service.dart';

typedef BrowserDiagnosticLogSink =
    Future<void> Function(
      String message, {
      Object? error,
      StackTrace? stackTrace,
      Map<String, Object?>? metadata,
    });

class BrowserWebViewDiagnostics {
  BrowserWebViewDiagnostics({
    BrowserDiagnosticLogSink? logSink,
    DateTime Function()? now,
  }) : _logSink = logSink ?? AppLogService.instance.log,
       _now = now ?? DateTime.now;

  final BrowserDiagnosticLogSink _logSink;
  final DateTime Function() _now;
  final Map<String, DateTime> _loadStartedAtByTab = <String, DateTime>{};

  void recordLoadStart({required String tabId, required String? url}) {
    _loadStartedAtByTab[tabId] = _now();
    _write(
      'Browser WebView load start',
      metadata: <String, Object?>{'tabId': tabId, 'url': safeUrl(url)},
    );
  }

  void recordLoadStop({required String tabId, required String? url}) {
    final startedAt = _loadStartedAtByTab.remove(tabId);
    final elapsedMilliseconds = startedAt == null
        ? null
        : _now().difference(startedAt).inMilliseconds;
    _write(
      'Browser WebView load stop',
      metadata: <String, Object?>{
        'tabId': tabId,
        'url': safeUrl(url),
        'elapsedMs': elapsedMilliseconds,
      },
    );
  }

  void recordResourceError({
    required String tabId,
    required String? url,
    required String description,
    required int? errorCode,
    required bool? isForMainFrame,
  }) {
    if (isForMainFrame == false) {
      return;
    }
    _loadStartedAtByTab.remove(tabId);
    _write(
      'Browser WebView resource error',
      metadata: <String, Object?>{
        'tabId': tabId,
        'url': safeUrl(url),
        'description': _truncate(description, 500),
        'errorCode': errorCode,
        'isForMainFrame': isForMainFrame,
      },
    );
  }

  void recordHttpError({
    required String tabId,
    required String? url,
    required int? statusCode,
    required String? reasonPhrase,
    required bool? isForMainFrame,
  }) {
    if (isForMainFrame == false) {
      return;
    }
    _write(
      'Browser WebView HTTP error',
      metadata: <String, Object?>{
        'tabId': tabId,
        'url': safeUrl(url),
        'statusCode': statusCode,
        'reasonPhrase': _truncate(reasonPhrase, 200),
        'isForMainFrame': isForMainFrame,
      },
    );
  }

  void recordRenderProcessGone({
    required String tabId,
    required bool didCrash,
    required Object? rendererPriorityAtExit,
  }) {
    _write(
      'Browser WebView render process gone',
      metadata: <String, Object?>{
        'tabId': tabId,
        'didCrash': didCrash,
        'rendererPriorityAtExit': rendererPriorityAtExit,
      },
    );
  }

  void recordForceRefresh({
    required String tabId,
    required String? url,
    required bool wasLoading,
    required int progress,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _write(
      error == null
          ? 'Browser WebView force refresh'
          : 'Browser WebView force refresh failed',
      error: error,
      stackTrace: stackTrace,
      metadata: <String, Object?>{
        'tabId': tabId,
        'url': safeUrl(url),
        'wasLoading': wasLoading,
        'progress': progress,
      },
    );
  }

  String? safeUrl(String? rawUrl) {
    final normalized = rawUrl?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.scheme.isEmpty) {
      return _truncate(normalized, 200);
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return '$scheme://';
    }
    final safeUri = Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: _truncate(uri.path, 240),
    );
    return safeUri.toString();
  }

  String? _truncate(String? value, int maxLength) {
    if (value == null || value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}…';
  }

  void _write(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) {
    unawaited(
      _logSink(
        message,
        error: error,
        stackTrace: stackTrace,
        metadata: metadata,
      ).catchError((_) {}),
    );
  }
}
