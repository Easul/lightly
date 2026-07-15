import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_history_entry.dart';
import 'package:lightly/browser/models/browser_suggestion.dart';
import 'package:lightly/browser/services/browser_history_service.dart';
import 'package:lightly/browser/services/browser_suggestion_service.dart';

void main() {
  test('returns only local history suggestions for prefix query', () async {
    final service = BrowserSuggestionService(
      historyService: _FakeBrowserHistoryService(),
      debounceDuration: Duration.zero,
    );

    final suggestions = await service.suggest('flutter');

    expect(
      _labels(suggestions),
      equals(<String>[
        'Flutter Documentation|https://flutter.dev',
        'Flutter API Docs|https://docs.flutter.dev',
      ]),
    );

    service.dispose();
  });

  test('returns top history entries for empty query', () async {
    final service = BrowserSuggestionService(
      historyService: _FakeBrowserHistoryService(),
      debounceDuration: Duration.zero,
    );

    final suggestions = await service.suggest('');

    expect(
      _labels(suggestions),
      equals(<String>[
        'Example|https://example.com',
        'Flutter Documentation|https://flutter.dev',
        'Flutter API Docs|https://docs.flutter.dev',
      ]),
    );

    service.dispose();
  });

  test('matches history by partial url substring', () async {
    final service = BrowserSuggestionService(
      historyService: _FakeBrowserHistoryService(),
      debounceDuration: Duration.zero,
    );

    final suggestions = await service.suggest('docs');

    expect(
      _labels(suggestions),
      equals(<String>['Flutter API Docs|https://docs.flutter.dev']),
    );

    service.dispose();
  });

  test('matches history by partial title substring', () async {
    final service = BrowserSuggestionService(
      historyService: _FakeBrowserHistoryService(),
      debounceDuration: Duration.zero,
    );

    final suggestions = await service.suggest('Document');

    expect(
      _labels(suggestions),
      equals(<String>['Flutter Documentation|https://flutter.dev']),
    );

    service.dispose();
  });

  test('reuses the same pending future for repeated query input', () async {
    final service = BrowserSuggestionService(
      historyService: _FakeBrowserHistoryService(),
      debounceDuration: const Duration(milliseconds: 10),
    );

    final firstFuture = service.suggest('flutter');
    final secondFuture = service.suggest('flutter');

    expect(identical(firstFuture, secondFuture), isTrue);
    expect(
      _labels(await secondFuture),
      equals(<String>[
        'Flutter Documentation|https://flutter.dev',
        'Flutter API Docs|https://docs.flutter.dev',
      ]),
    );

    service.dispose();
  });
}

List<String> _labels(List<BrowserSuggestion> suggestions) {
  return suggestions
      .map((suggestion) => '${suggestion.title}|${suggestion.url}')
      .toList(growable: false);
}

class _FakeBrowserHistoryService extends BrowserHistoryService {
  @override
  Future<List<BrowserHistoryEntry>> getTop({int limit = 8}) async {
    return <BrowserHistoryEntry>[
      BrowserHistoryEntry(
        id: 1,
        url: 'https://example.com',
        title: 'Example',
        visitedAt: DateTime.utc(2024, 1, 1),
        visitCount: 3,
      ),
      BrowserHistoryEntry(
        id: 2,
        url: 'https://flutter.dev',
        title: 'Flutter Documentation',
        visitedAt: DateTime.utc(2024, 1, 2),
        visitCount: 5,
      ),
      BrowserHistoryEntry(
        id: 3,
        url: 'https://docs.flutter.dev',
        title: 'Flutter API Docs',
        visitedAt: DateTime.utc(2024, 1, 3),
        visitCount: 4,
      ),
    ].take(limit).toList(growable: false);
  }

  @override
  Future<List<BrowserHistoryEntry>> query({
    String? searchTerm,
    int limit = 50,
  }) async {
    final normalized = searchTerm?.trim().toLowerCase();
    final allEntries = await getTop(limit: 10);
    if (normalized == null || normalized.isEmpty) {
      return allEntries.take(limit).toList(growable: false);
    }

    return allEntries
        .where((entry) {
          return entry.url.toLowerCase().contains(normalized) ||
              entry.title.toLowerCase().contains(normalized);
        })
        .take(limit)
        .toList(growable: false);
  }
}
