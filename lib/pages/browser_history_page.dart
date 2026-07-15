import 'dart:async';

import 'package:flutter/material.dart';

import '../browser/models/browser_history_visit.dart';
import '../browser/services/browser_history_service.dart';
import '../browser/services/browser_shared_services.dart';
import '../services/app_toast.dart';

class BrowserHistoryPageResult {
  const BrowserHistoryPageResult(this.url);

  final String url;
}

class BrowserHistoryPage extends StatefulWidget {
  const BrowserHistoryPage({super.key, this.historyService});

  final BrowserHistoryService? historyService;

  @override
  State<BrowserHistoryPage> createState() => _BrowserHistoryPageState();
}

class _BrowserHistoryPageState extends State<BrowserHistoryPage> {
  static const int _pageSize = 50;

  late final BrowserHistoryService _historyService;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<BrowserHistoryVisit> _visits = <BrowserHistoryVisit>[];

  Timer? _searchDebounce;
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _historyService =
        widget.historyService ?? BrowserSharedServices.instance.historyService;
    _scrollController.addListener(_handleScroll);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.position.extentAfter < 360) {
      unawaited(_loadMore());
    }
  }

  void _handleSearchChanged(String value) {
    if (mounted) {
      setState(() {});
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    final requestId = ++_requestId;
    if (mounted) {
      setState(() {
        _isInitialLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
      });
    }

    try {
      final visits = await _historyService.queryVisits(
        searchTerm: _searchController.text,
        limit: _pageSize,
      );
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _visits
          ..clear()
          ..addAll(visits);
        _hasMore = visits.length == _pageSize;
        _isInitialLoading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() => _isInitialLoading = false);
      _showToast('读取浏览历史失败');
    }
  }

  Future<void> _loadMore() async {
    if (_isInitialLoading || _isLoadingMore || !_hasMore || _visits.isEmpty) {
      return;
    }
    setState(() => _isLoadingMore = true);
    final requestId = _requestId;
    final lastVisit = _visits.last;
    try {
      final visits = await _historyService.queryVisits(
        searchTerm: _searchController.text,
        beforeVisitedAt: lastVisit.visitedAt,
        beforeId: lastVisit.id,
        limit: _pageSize,
      );
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _visits.addAll(visits);
        _hasMore = visits.length == _pageSize;
      });
    } catch (_) {
      if (mounted && requestId == _requestId) {
        _showToast('加载更多浏览历史失败');
      }
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _confirmClearHistory() async {
    if (_visits.isEmpty && _searchController.text.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空浏览历史？'),
        content: const Text('此操作只会清除浏览历史，不会删除 Cookie、缓存和登录状态。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      await _historyService.clearHistory();
      if (!mounted) {
        return;
      }
      setState(() {
        _visits.clear();
        _hasMore = false;
      });
      _showToast('浏览历史已清空');
    } catch (_) {
      _showToast('清空浏览历史失败');
    }
  }

  Future<void> _confirmDelete(BrowserHistoryVisit visit) async {
    final displayTitle = visit.title.trim().isEmpty ? visit.url : visit.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条浏览记录？'),
        content: Text(
          displayTitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      await _historyService.deleteVisit(visit);
      if (!mounted) {
        return;
      }
      setState(() => _visits.removeWhere((item) => item.id == visit.id));
    } catch (_) {
      _showToast('删除浏览记录失败');
    }
  }

  void _openVisit(BrowserHistoryVisit visit) {
    final uri = Uri.tryParse(visit.url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _showToast('该浏览记录链接无效');
      return;
    }
    Navigator.pop(context, BrowserHistoryPageResult(visit.url));
  }

  List<_HistoryRow> _buildRows() {
    final rows = <_HistoryRow>[];
    DateTime? previousDate;
    for (final visit in _visits) {
      final date = DateTime(
        visit.visitedAt.year,
        visit.visitedAt.month,
        visit.visitedAt.day,
      );
      if (previousDate != date) {
        rows.add(_HistoryRow.date(_dateLabel(date)));
        previousDate = date;
      }
      rows.add(_HistoryRow.visit(visit));
    }
    return rows;
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(date).inDays;
    if (difference == 0) {
      return '今天';
    }
    if (difference == 1) {
      return '昨天';
    }
    if (date.year == today.year) {
      return '${date.month}月${date.day}日';
    }
    return '${date.year}年${date.month}月${date.day}日';
  }

  void _showToast(String message) {
    unawaited(AppToast.show(message));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rows = _buildRows();
    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览历史'),
        actions: [
          TextButton(onPressed: _confirmClearHistory, child: const Text('清空')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _handleSearchChanged,
              decoration: InputDecoration(
                hintText: '搜索标题或链接',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _handleSearchChanged('');
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: _isInitialLoading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                ? _HistoryEmptyState(
                    hasQuery: _searchController.text.isNotEmpty,
                  )
                : ListView.builder(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: rows.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == rows.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final row = rows[index];
                      if (row.dateLabel != null) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                          child: Text(
                            row.dateLabel!,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        );
                      }
                      final visit = row.visit!;
                      final title = visit.title.trim().isEmpty
                          ? visit.url
                          : visit.title.trim();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 0,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          title: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              visit.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          onTap: () => _openVisit(visit),
                          onLongPress: () => _confirmDelete(visit),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow {
  const _HistoryRow.date(this.dateLabel) : visit = null;
  const _HistoryRow.visit(this.visit) : dateLabel = null;

  final String? dateLabel;
  final BrowserHistoryVisit? visit;
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 44, color: colorScheme.outline),
          const SizedBox(height: 12),
          Text(hasQuery ? '没有匹配的浏览记录' : '暂无浏览历史'),
        ],
      ),
    );
  }
}
