import 'package:sqflite/sqflite.dart';

import '../data/browser_database.dart';
import '../models/browser_history_entry.dart';

class BrowserHistoryService {
  BrowserHistoryService({BrowserDatabase? database})
    : _database = database ?? BrowserDatabase.instance;

  final BrowserDatabase _database;

  Future<BrowserHistoryEntry> insert({
    required String url,
    required String title,
    DateTime? visitedAt,
  }) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw ArgumentError.value(url, 'url', 'URL cannot be empty.');
    }

    final normalizedTitle = title.trim().isEmpty ? trimmedUrl : title.trim();
    final visitTime = visitedAt ?? DateTime.now();
    final db = await _database.database;

    return db.transaction((txn) async {
      final existingRows = await txn.query(
        BrowserDatabase.historyTable,
        where: 'url = ?',
        whereArgs: [trimmedUrl],
        limit: 1,
      );

      if (existingRows.isNotEmpty) {
        final existingEntry = BrowserHistoryEntry.fromMap(existingRows.first);
        final updatedEntry = existingEntry.copyWith(
          title: normalizedTitle,
          visitedAt: visitTime,
          visitCount: existingEntry.visitCount + 1,
        );
        await txn.update(
          BrowserDatabase.historyTable,
          updatedEntry.toMap()..remove('id'),
          where: 'id = ?',
          whereArgs: [existingEntry.id],
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return updatedEntry;
      }

      final entry = BrowserHistoryEntry(
        url: trimmedUrl,
        title: normalizedTitle,
        visitedAt: visitTime,
        visitCount: 1,
      );
      final id = await txn.insert(
        BrowserDatabase.historyTable,
        entry.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return entry.copyWith(id: id);
    });
  }

  Future<List<BrowserHistoryEntry>> query({
    String? searchTerm,
    int limit = 50,
  }) async {
    final db = await _database.database;
    final normalizedSearchTerm = searchTerm?.trim();

    final rows = await db.query(
      BrowserDatabase.historyTable,
      where: normalizedSearchTerm != null && normalizedSearchTerm.isNotEmpty
          ? '(url LIKE ? OR title LIKE ?)'
          : null,
      whereArgs: normalizedSearchTerm != null && normalizedSearchTerm.isNotEmpty
          ? ['%$normalizedSearchTerm%', '%$normalizedSearchTerm%']
          : null,
      orderBy: 'visitedAt DESC',
      limit: limit,
    );

    return rows.map(BrowserHistoryEntry.fromMap).toList();
  }

  Future<void> clearHistory() async {
    final db = await _database.database;
    await db.delete(BrowserDatabase.historyTable);
  }

  Future<List<BrowserHistoryEntry>> prefixSearch(
    String prefix, {
    int limit = 5,
  }) async {
    final normalizedPrefix = prefix.trim();
    if (normalizedPrefix.isEmpty) {
      return [];
    }

    final db = await _database.database;
    final rows = await db.query(
      BrowserDatabase.historyTable,
      where: '(url LIKE ? OR title LIKE ?)',
      whereArgs: ['$normalizedPrefix%', '$normalizedPrefix%'],
      orderBy: 'visitCount DESC, visitedAt DESC',
      limit: limit,
    );
    return rows.map(BrowserHistoryEntry.fromMap).toList();
  }

  Future<List<BrowserHistoryEntry>> getTop({int limit = 8}) async {
    final db = await _database.database;
    final rows = await db.query(
      BrowserDatabase.historyTable,
      orderBy: 'visitCount DESC, visitedAt DESC',
      limit: limit,
    );
    return rows.map(BrowserHistoryEntry.fromMap).toList();
  }
}
