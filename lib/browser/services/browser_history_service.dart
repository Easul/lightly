import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../models/browser_history_entry.dart';
import '../models/browser_history_visit.dart';

class BrowserHistoryService {
  BrowserHistoryService({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

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
      await txn.insert(
        AppDatabase.historyVisitsTable,
        BrowserHistoryVisit(
          url: trimmedUrl,
          title: normalizedTitle,
          visitedAt: visitTime,
        ).toMap()..remove('id'),
      );

      final existingRows = await txn.query(
        AppDatabase.historyTable,
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
          AppDatabase.historyTable,
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
        AppDatabase.historyTable,
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
      AppDatabase.historyTable,
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
    await db.transaction((txn) async {
      await txn.delete(AppDatabase.historyVisitsTable);
      await txn.delete(AppDatabase.historyTable);
    });
  }

  Future<void> updateLatestTitle({
    required String url,
    required String title,
  }) async {
    final trimmedUrl = url.trim();
    final trimmedTitle = title.trim();
    if (trimmedUrl.isEmpty || trimmedTitle.isEmpty) {
      return;
    }

    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.update(
        AppDatabase.historyTable,
        <String, Object?>{'title': trimmedTitle},
        where: 'url = ?',
        whereArgs: <Object?>[trimmedUrl],
      );
      final latestRows = await txn.query(
        AppDatabase.historyVisitsTable,
        columns: <String>['id'],
        where: 'url = ?',
        whereArgs: <Object?>[trimmedUrl],
        orderBy: 'visitedAt DESC, id DESC',
        limit: 1,
      );
      if (latestRows.isNotEmpty) {
        await txn.update(
          AppDatabase.historyVisitsTable,
          <String, Object?>{'title': trimmedTitle},
          where: 'id = ?',
          whereArgs: <Object?>[latestRows.first['id']],
        );
      }
    });
  }

  Future<List<BrowserHistoryVisit>> queryVisits({
    String? searchTerm,
    DateTime? beforeVisitedAt,
    int? beforeId,
    int limit = 50,
  }) async {
    final db = await _database.database;
    final normalizedSearchTerm = searchTerm?.trim();
    final whereParts = <String>[];
    final whereArgs = <Object?>[];

    if (normalizedSearchTerm != null && normalizedSearchTerm.isNotEmpty) {
      whereParts.add('(url LIKE ? OR title LIKE ?)');
      whereArgs.addAll(<Object?>[
        '%$normalizedSearchTerm%',
        '%$normalizedSearchTerm%',
      ]);
    }

    if (beforeVisitedAt != null && beforeId != null) {
      whereParts.add('(visitedAt < ? OR (visitedAt = ? AND id < ?))');
      final timestamp = beforeVisitedAt.millisecondsSinceEpoch;
      whereArgs.addAll(<Object?>[timestamp, timestamp, beforeId]);
    }

    final rows = await db.query(
      AppDatabase.historyVisitsTable,
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'visitedAt DESC, id DESC',
      limit: limit,
    );
    return rows.map(BrowserHistoryVisit.fromMap).toList(growable: false);
  }

  Future<void> deleteVisit(BrowserHistoryVisit visit) async {
    final visitId = visit.id;
    if (visitId == null) {
      return;
    }

    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.historyVisitsTable,
        where: 'id = ?',
        whereArgs: <Object?>[visitId],
      );

      final remaining = await txn.query(
        AppDatabase.historyVisitsTable,
        where: 'url = ?',
        whereArgs: <Object?>[visit.url],
        orderBy: 'visitedAt DESC, id DESC',
        limit: 1,
      );
      if (remaining.isEmpty) {
        await txn.delete(
          AppDatabase.historyTable,
          where: 'url = ?',
          whereArgs: <Object?>[visit.url],
        );
        return;
      }

      final latest = BrowserHistoryVisit.fromMap(remaining.first);
      final countRows = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM ${AppDatabase.historyVisitsTable} '
        'WHERE url = ?',
        <Object?>[visit.url],
      );
      final visitCount = (countRows.first['count'] as num?)?.toInt() ?? 0;
      await txn.update(
        AppDatabase.historyTable,
        <String, Object?>{
          'title': latest.title,
          'visitedAt': latest.visitedAt.millisecondsSinceEpoch,
          'visitCount': visitCount,
        },
        where: 'url = ?',
        whereArgs: <Object?>[visit.url],
      );
    });
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
      AppDatabase.historyTable,
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
      AppDatabase.historyTable,
      orderBy: 'visitCount DESC, visitedAt DESC',
      limit: limit,
    );
    return rows.map(BrowserHistoryEntry.fromMap).toList();
  }
}
