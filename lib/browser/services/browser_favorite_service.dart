import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../models/browser_favorite.dart';
import '../utils/browser_url_utils.dart';

class BrowserFavoriteService {
  BrowserFavoriteService({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  String _normalizeComparableUrl(String url) {
    final trimmed = remapImportedDocumentFileUrl(url.trim());
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return trimmed;
    }

    final normalizedPath = uri.path.isEmpty || uri.path == '/'
        ? ''
        : uri.path.replaceAll(RegExp(r'/+$'), '');
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: normalizedPath,
          fragment: null,
        )
        .toString();
  }

  Future<BrowserFavorite> insert({
    required String url,
    required String title,
    int? sortOrder,
  }) async {
    final trimmedUrl = _normalizeComparableUrl(url);
    final normalizedTitle = title.trim().isEmpty ? trimmedUrl : title.trim();
    if (trimmedUrl.isEmpty) {
      throw ArgumentError.value(url, 'url', 'URL cannot be empty.');
    }

    final db = await _database.database;
    final now = DateTime.now();

    // Get max sortOrder if not provided
    var order = sortOrder;
    if (order == null) {
      final maxResult = await db.rawQuery(
        'SELECT MAX(sortOrder) as maxOrder FROM ${AppDatabase.favoriteTable}',
      );
      order = ((maxResult.first['maxOrder'] as num?)?.toInt() ?? -1) + 1;
    }

    final favorite = BrowserFavorite(
      url: trimmedUrl,
      title: normalizedTitle,
      createdAt: now,
      sortOrder: order,
    );

    final id = await db.insert(
      AppDatabase.favoriteTable,
      favorite.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return favorite.copyWith(id: id);
  }

  Future<List<BrowserFavorite>> query({String? searchTerm}) async {
    final db = await _database.database;
    final normalizedSearchTerm = searchTerm?.trim();

    final rows = await db.query(
      AppDatabase.favoriteTable,
      where: normalizedSearchTerm != null && normalizedSearchTerm.isNotEmpty
          ? '(url LIKE ? OR title LIKE ?)'
          : null,
      whereArgs: normalizedSearchTerm != null && normalizedSearchTerm.isNotEmpty
          ? ['%$normalizedSearchTerm%', '%$normalizedSearchTerm%']
          : null,
      orderBy: 'sortOrder ASC, createdAt DESC',
    );

    return rows.map(BrowserFavorite.fromMap).toList();
  }

  Future<BrowserFavorite?> findByUrl(String url) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.favoriteTable,
      where: 'url = ?',
      whereArgs: [_normalizeComparableUrl(url)],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return BrowserFavorite.fromMap(rows.first);
  }

  Future<void> update(BrowserFavorite favorite) async {
    final db = await _database.database;
    await db.update(
      AppDatabase.favoriteTable,
      favorite.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [favorite.id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(int id) async {
    final db = await _database.database;
    await db.delete(
      AppDatabase.favoriteTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final db = await _database.database;
    final favorites = await query();

    if (oldIndex < 0 ||
        oldIndex >= favorites.length ||
        newIndex < 0 ||
        newIndex >= favorites.length) {
      return;
    }

    final item = favorites.removeAt(oldIndex);
    favorites.insert(newIndex, item);

    await db.transaction((txn) async {
      for (var i = 0; i < favorites.length; i++) {
        await txn.update(
          AppDatabase.favoriteTable,
          {'sortOrder': i},
          where: 'id = ?',
          whereArgs: [favorites[i].id],
        );
      }
    });
  }

  Future<void> clearAll() async {
    final db = await _database.database;
    await db.delete(AppDatabase.favoriteTable);
  }
}
