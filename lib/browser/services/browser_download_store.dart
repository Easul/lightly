import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../models/browser_download_record.dart';

class BrowserDownloadStore {
  BrowserDownloadStore({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  static final ValueNotifier<int> _changeNotifier = ValueNotifier<int>(0);

  final AppDatabase _database;

  ValueListenable<int> get changes => _changeNotifier;

  void _notifyChanged() {
    _changeNotifier.value = _changeNotifier.value + 1;
  }

  Future<BrowserDownloadRecord> insert(BrowserDownloadRecord record) async {
    final db = await _database.database;
    final id = await db.insert(
      AppDatabase.downloadTable,
      record.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyChanged();
    return record.copyWith(id: id);
  }

  Future<void> update(BrowserDownloadRecord record) async {
    final id = record.id;
    if (id == null) {
      throw ArgumentError.value(
        record.id,
        'record.id',
        'Record id is required.',
      );
    }

    final db = await _database.database;
    await db.update(
      AppDatabase.downloadTable,
      record.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
    _notifyChanged();
  }

  Future<void> delete(int id) async {
    final db = await _database.database;
    await db.delete(
      AppDatabase.downloadTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    _notifyChanged();
  }

  Future<void> clearAll() async {
    final db = await _database.database;
    await db.delete(AppDatabase.downloadTable);
    _notifyChanged();
  }

  Future<BrowserDownloadRecord?> query(int id) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.downloadTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return BrowserDownloadRecord.fromMap(rows.first);
  }

  Future<List<BrowserDownloadRecord>> list({
    String? status,
    int? limit = 100,
  }) async {
    final db = await _database.database;
    final normalizedStatus = status?.trim();
    final rows = await db.query(
      AppDatabase.downloadTable,
      where: normalizedStatus != null && normalizedStatus.isNotEmpty
          ? 'status = ?'
          : null,
      whereArgs: normalizedStatus != null && normalizedStatus.isNotEmpty
          ? [normalizedStatus]
          : null,
      orderBy: 'createdAt DESC',
      limit: limit,
    );
    return rows.map(BrowserDownloadRecord.fromMap).toList();
  }
}
