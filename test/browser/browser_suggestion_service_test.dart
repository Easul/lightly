import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_history_entry.dart';
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
      suggestions,
      equals(<String>['https://flutter.dev', 'Flutter Documentation']),
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
      suggestions,
      equals(<String>[
        'https://example.com',
        'Example',
        'https://flutter.dev',
        'Flutter Documentation',
      ]),
    );

    service.dispose();
  });
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
    ].take(limit).toList(growable: false);
  }

  @override
  Future<List<BrowserHistoryEntry>> prefixSearch(
    String prefix, {
    int limit = 5,
  }) async {
    if (prefix == 'flutter') {
      return <BrowserHistoryEntry>[
        BrowserHistoryEntry(
          id: 2,
          url: 'https://flutter.dev',
          title: 'Flutter Documentation',
          visitedAt: DateTime.utc(2024, 1, 2),
          visitCount: 5,
        ),
      ];
    }
    return const <BrowserHistoryEntry>[];
  }
}
