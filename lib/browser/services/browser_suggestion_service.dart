import 'dart:async';

import '../models/browser_history_entry.dart';
import '../models/browser_suggestion.dart';
import 'browser_history_service.dart';

class _LruCacheEntry<V> {
  final V value;
  int accessCount;
  DateTime lastAccessed;
  _LruCacheEntry(
    this.value, {
    this.accessCount = 1,
    required this.lastAccessed,
  });

  void touch() {
    accessCount++;
    lastAccessed = DateTime.now();
  }
}

class BrowserSuggestionService {
  BrowserSuggestionService({
    BrowserHistoryService? historyService,
    Duration debounceDuration = const Duration(milliseconds: 300),
    int maxCacheSize = 100,
  }) : _historyService = historyService ?? BrowserHistoryService(),
       _debounceDuration = debounceDuration,
       _maxCacheSize = maxCacheSize;

  final BrowserHistoryService _historyService;
  final Duration _debounceDuration;
  final int _maxCacheSize;

  Timer? _debounceTimer;
  Completer<List<BrowserSuggestion>>? _pendingCompleter;
  final Map<String, _LruCacheEntry<List<BrowserSuggestion>>> _suggestionCache =
      {};
  String? _lastIssuedQuery;

  Future<List<BrowserSuggestion>> suggest(String query) {
    final normalizedQuery = query.trim();
    final cachedEntry = _suggestionCache[normalizedQuery];
    if (cachedEntry != null) {
      cachedEntry.touch();
      return Future.value(cachedEntry.value);
    }

    if (_lastIssuedQuery == normalizedQuery && _pendingCompleter != null) {
      return _pendingCompleter!.future;
    }

    _debounceTimer?.cancel();
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(<BrowserSuggestion>[]);
    }

    final completer = Completer<List<BrowserSuggestion>>();
    _pendingCompleter = completer;
    _lastIssuedQuery = normalizedQuery;

    _debounceTimer = Timer(_debounceDuration, () async {
      try {
        if (normalizedQuery.isEmpty) {
          final topEntries = await _historyService.getTop(limit: 6);
          final results = _mapHistoryEntries(topEntries, normalizedQuery);
          _putCache(normalizedQuery, results);
          if (!completer.isCompleted) {
            completer.complete(results);
          }
          return;
        }

        final historyEntries = await _historyService.query(
          searchTerm: normalizedQuery,
          limit: 50,
        );
        final results = _mapHistoryEntries(historyEntries, normalizedQuery);

        _putCache(normalizedQuery, results);
        if (!completer.isCompleted) {
          completer.complete(results);
        }
      } catch (_) {
        if (!completer.isCompleted) {
          completer.complete(<BrowserSuggestion>[]);
        }
      } finally {
        if (identical(_pendingCompleter, completer)) {
          _pendingCompleter = null;
        }
        if (_lastIssuedQuery == normalizedQuery) {
          _lastIssuedQuery = null;
        }
      }
    });

    return completer.future;
  }

  List<BrowserSuggestion> _mapHistoryEntries(
    List<BrowserHistoryEntry> entries,
    String query,
  ) {
    final results = <BrowserSuggestion>[];
    final loweredQuery = query.toLowerCase();
    final isEmptyQuery = loweredQuery.isEmpty;

    if (!isEmptyQuery) {
      entries.sort((left, right) {
        final scoreComparison = _matchScore(
          right,
          loweredQuery,
        ).compareTo(_matchScore(left, loweredQuery));
        if (scoreComparison != 0) {
          return scoreComparison;
        }
        final countComparison = right.visitCount.compareTo(left.visitCount);
        if (countComparison != 0) {
          return countComparison;
        }
        return right.visitedAt.compareTo(left.visitedAt);
      });
    }

    for (final entry in entries) {
      final url = entry.url.trim();
      final normalizedTitle = entry.title.trim().isEmpty
          ? url
          : entry.title.trim();
      final loweredTitle = normalizedTitle.toLowerCase();
      final loweredUrl = url.toLowerCase();

      final titleMatches = isEmptyQuery || loweredTitle.contains(loweredQuery);
      final urlMatches = isEmptyQuery || loweredUrl.contains(loweredQuery);
      if (url.isNotEmpty && (urlMatches || titleMatches)) {
        results.add(
          BrowserSuggestion(
            title: normalizedTitle,
            url: url,
            visitCount: entry.visitCount,
            visitedAt: entry.visitedAt,
          ),
        );
      }

      if (results.length >= 6) {
        break;
      }
    }

    return results;
  }

  int _matchScore(BrowserHistoryEntry entry, String query) {
    final title = entry.title.trim().toLowerCase();
    final url = entry.url.trim().toLowerCase();
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (title.startsWith(query) || host.startsWith(query)) {
      return 3;
    }
    if (url.startsWith(query)) {
      return 2;
    }
    if (title.contains(query) || url.contains(query)) {
      return 1;
    }
    return 0;
  }

  void _putCache(String key, List<BrowserSuggestion> value) {
    if (_suggestionCache.length >= _maxCacheSize &&
        !_suggestionCache.containsKey(key)) {
      _evictIfNeeded();
    }
    _suggestionCache[key] = _LruCacheEntry<List<BrowserSuggestion>>(
      value,
      lastAccessed: DateTime.now(),
    );
  }

  void _evictIfNeeded() {
    if (_suggestionCache.isEmpty) return;

    // LFU + LRU hybrid eviction
    // Find entry with lowest access count, and among those, oldest lastAccessed
    String? keyToEvict;
    int minAccessCount = -1;
    DateTime? oldestAccessTime;

    _suggestionCache.forEach((key, entry) {
      if (keyToEvict == null ||
          entry.accessCount < minAccessCount ||
          (entry.accessCount == minAccessCount &&
              entry.lastAccessed.isBefore(oldestAccessTime!))) {
        keyToEvict = key;
        minAccessCount = entry.accessCount;
        oldestAccessTime = entry.lastAccessed;
      }
    });

    if (keyToEvict != null) {
      _suggestionCache.remove(keyToEvict);
    }
  }

  void clearCache() {
    _suggestionCache.clear();
    _lastIssuedQuery = null;
  }

  void dispose() {
    _debounceTimer?.cancel();
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(<BrowserSuggestion>[]);
    }
    _pendingCompleter = null;
    _lastIssuedQuery = null;
  }
}
