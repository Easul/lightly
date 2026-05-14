import 'dart:async';

import '../models/browser_history_entry.dart';
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
  Completer<List<String>>? _pendingCompleter;
  final Map<String, _LruCacheEntry<List<String>>> _suggestionCache = {};
  String? _lastIssuedQuery;

  Future<List<String>> suggest(String query) {
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
      _pendingCompleter!.complete(<String>[]);
    }

    final completer = Completer<List<String>>();
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
          limit: 6,
        );
        final results = _mapHistoryEntries(historyEntries, normalizedQuery);

        _putCache(normalizedQuery, results);
        if (!completer.isCompleted) {
          completer.complete(results);
        }
      } catch (_) {
        if (!completer.isCompleted) {
          completer.complete(<String>[]);
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

  List<String> _mapHistoryEntries(
    List<BrowserHistoryEntry> entries,
    String query,
  ) {
    final results = <String>[];
    final loweredQuery = query.toLowerCase();
    final isEmptyQuery = loweredQuery.isEmpty;

    for (final entry in entries) {
      final url = entry.url;
      final title = entry.title;

      final normalizedTitle = title.trim();
      final loweredTitle = normalizedTitle.toLowerCase();
      final loweredUrl = url.toLowerCase();

      final titleMatches = isEmptyQuery || loweredTitle.contains(loweredQuery);
      final urlMatches = isEmptyQuery || loweredUrl.contains(loweredQuery);
      final shouldIncludeUrl = urlMatches || titleMatches;

      if (url.isNotEmpty && shouldIncludeUrl && !results.contains(url)) {
        results.add(url);
      }

      if (normalizedTitle.isNotEmpty &&
          titleMatches &&
          !results.contains(normalizedTitle)) {
        results.add(normalizedTitle);
      }

      if (results.length >= 6) {
        break;
      }
    }

    return results;
  }

  void _putCache(String key, List<String> value) {
    if (_suggestionCache.length >= _maxCacheSize &&
        !_suggestionCache.containsKey(key)) {
      _evictIfNeeded();
    }
    _suggestionCache[key] = _LruCacheEntry<List<String>>(
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
      _pendingCompleter!.complete(<String>[]);
    }
    _pendingCompleter = null;
    _lastIssuedQuery = null;
  }
}
