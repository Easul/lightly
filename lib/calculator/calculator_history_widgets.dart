import 'package:flutter/material.dart';

import 'calculation_history.dart';

class CalculatorHistoryTab extends StatelessWidget {
  const CalculatorHistoryTab({
    super.key,
    required this.searchController,
    required this.isLoading,
    required this.filteredHistory,
    required this.hasHistory,
    required this.onClearAllHistory,
    required this.onDeleteEntry,
    required this.onEntryTap,
    required this.onEntryLongPress,
  });

  final TextEditingController searchController;
  final bool isLoading;
  final List<CalculationHistory> filteredHistory;
  final bool hasHistory;
  final Future<void> Function() onClearAllHistory;
  final Future<void> Function(String id) onDeleteEntry;
  final ValueChanged<CalculationHistory> onEntryTap;
  final ValueChanged<CalculationHistory> onEntryLongPress;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HistorySearchField(searchController: searchController),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredHistory.isEmpty
              ? _HistoryEmptyState(
                  isSearching: searchController.text.isNotEmpty,
                )
              : _HistoryList(
                  entries: filteredHistory,
                  hasHistory: hasHistory,
                  onClearAllHistory: onClearAllHistory,
                  onDeleteEntry: onDeleteEntry,
                  onEntryTap: onEntryTap,
                  onEntryLongPress: onEntryLongPress,
                ),
        ),
      ],
    );
  }
}

class _HistorySearchField extends StatelessWidget {
  const _HistorySearchField({required this.searchController});

  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: searchController,
        decoration: InputDecoration(
          labelText: '搜索历史',
          hintText: '搜索表达式、结果或备注',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: searchController.clear,
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({required this.isSearching});

  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            isSearching ? '未找到匹配的记录' : '暂无计算历史',
            style: TextStyle(fontSize: 16, color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.entries,
    required this.hasHistory,
    required this.onClearAllHistory,
    required this.onDeleteEntry,
    required this.onEntryTap,
    required this.onEntryLongPress,
  });

  final List<CalculationHistory> entries;
  final bool hasHistory;
  final Future<void> Function() onClearAllHistory;
  final Future<void> Function(String id) onDeleteEntry;
  final ValueChanged<CalculationHistory> onEntryTap;
  final ValueChanged<CalculationHistory> onEntryLongPress;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      itemCount: entries.length + (hasHistory ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasHistory && index == entries.length) {
          return _ClearHistoryButton(onClearAllHistory: onClearAllHistory);
        }
        final entry = entries[index];
        return _HistoryEntryTile(
          entry: entry,
          onDeleteEntry: onDeleteEntry,
          onTap: onEntryTap,
          onLongPress: onEntryLongPress,
        );
      },
    );
  }
}

class _ClearHistoryButton extends StatelessWidget {
  const _ClearHistoryButton({required this.onClearAllHistory});

  final Future<void> Function() onClearAllHistory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 24.0),
      child: ElevatedButton.icon(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('确认清空'),
              content: const Text('确定要清空所有历史记录吗？此操作不可恢复。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('清空'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await onClearAllHistory();
          }
        },
        icon: const Icon(Icons.delete_forever),
        label: const Text('清空历史'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    );
  }
}

class _HistoryEntryTile extends StatelessWidget {
  const _HistoryEntryTile({
    required this.entry,
    required this.onDeleteEntry,
    required this.onTap,
    required this.onLongPress,
  });

  final CalculationHistory entry;
  final Future<void> Function(String id) onDeleteEntry;
  final ValueChanged<CalculationHistory> onTap;
  final ValueChanged<CalculationHistory> onLongPress;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认删除'),
            content: const Text('确定要删除这条记录吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDeleteEntry(entry.id),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          title: Text(
            '${entry.expression} = ${entry.result}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_formatDateTime(entry.createdAt)),
              if (entry.note.isNotEmpty)
                Text(
                  '备注: ${entry.note}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
          onTap: () => onTap(entry),
          onLongPress: () => onLongPress(entry),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
