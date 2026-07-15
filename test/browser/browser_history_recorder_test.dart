import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_history_entry.dart';
import 'package:lightly/browser/services/browser_history_recorder.dart';
import 'package:lightly/browser/services/browser_history_service.dart';

void main() {
  group('BrowserHistoryRecorder', () {
    late _FakeBrowserHistoryService historyService;
    late BrowserHistoryRecorder recorder;

    setUp(() {
      historyService = _FakeBrowserHistoryService();
      recorder = BrowserHistoryRecorder(historyService: historyService);
    });

    test('throttles rapid visited-history updates for the same url', () {
      final uri = Uri.parse('https://example.com');

      final first = recorder.shouldHandleVisitedHistoryUpdate(uri);
      final second = recorder.shouldHandleVisitedHistoryUpdate(uri);

      expect(first, isTrue);
      expect(second, isFalse);
    });

    test('records non-empty history once during dedupe window', () async {
      final url = WebUri('https://example.com');

      await recorder.recordHistory(url, 'Example');
      await recorder.recordHistory(url, 'Example');

      expect(historyService.recordedUrls, ['https://example.com']);
      expect(historyService.recordedTitles, ['Example']);
    });

    test('updates title received during the dedupe window', () async {
      final url = WebUri('https://example.com');

      await recorder.recordHistory(url, 'https://example.com');
      await recorder.recordHistory(url, 'Example title');

      expect(historyService.recordedUrls, ['https://example.com']);
      expect(historyService.updatedTitles, ['Example title']);
    });

    test('skips empty history urls', () async {
      await recorder.recordHistory(null, 'Ignored');

      expect(historyService.recordedUrls, isEmpty);
    });

    test('skips internal and local urls', () async {
      await recorder.recordHistory(WebUri('about:blank'), 'Blank');
      await recorder.recordHistory(WebUri('file:///tmp/demo.html'), 'Local');

      expect(historyService.recordedUrls, isEmpty);
    });
  });
}

class _FakeBrowserHistoryService extends BrowserHistoryService {
  final List<String> recordedUrls = <String>[];
  final List<String> recordedTitles = <String>[];
  final List<String> updatedTitles = <String>[];

  @override
  Future<BrowserHistoryEntry> insert({
    required String url,
    required String title,
    DateTime? visitedAt,
  }) async {
    recordedUrls.add(url);
    recordedTitles.add(title);
    return BrowserHistoryEntry(
      url: url,
      title: title,
      visitedAt: visitedAt ?? DateTime.now(),
      visitCount: 1,
    );
  }

  @override
  Future<void> updateLatestTitle({
    required String url,
    required String title,
  }) async {
    updatedTitles.add(title);
  }
}
