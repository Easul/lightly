import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_history_service.dart';

class BrowserHistoryRecorder {
  BrowserHistoryRecorder({BrowserHistoryService? historyService})
    : _historyService = historyService ?? BrowserHistoryService();

  final BrowserHistoryService _historyService;

  String _lastRecordedHistoryUrl = '';
  DateTime _lastHistoryRecordTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastVisitedHistoryUrl = '';
  DateTime _lastVisitedHistoryTime = DateTime.fromMillisecondsSinceEpoch(0);

  bool shouldHandleVisitedHistoryUpdate(Uri requestedUrl) {
    final urlString = requestedUrl.toString();
    final now = DateTime.now();
    if (_lastVisitedHistoryUrl == urlString &&
        now.difference(_lastVisitedHistoryTime) <
            const Duration(milliseconds: 200)) {
      return false;
    }

    _lastVisitedHistoryUrl = urlString;
    _lastVisitedHistoryTime = now;
    return true;
  }

  Future<void> recordHistory(WebUri? url, String title) async {
    final normalizedUrl = url?.toString().trim() ?? '';
    if (normalizedUrl.isEmpty) {
      return;
    }

    final now = DateTime.now();
    if (_lastRecordedHistoryUrl == normalizedUrl &&
        now.difference(_lastHistoryRecordTime) < const Duration(seconds: 2)) {
      return;
    }

    _lastRecordedHistoryUrl = normalizedUrl;
    _lastHistoryRecordTime = now;

    await _historyService.insert(
      url: normalizedUrl,
      title: title.trim().isEmpty ? normalizedUrl : title,
    );
  }
}
