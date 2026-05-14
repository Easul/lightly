import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class BrowserDatabase {
  BrowserDatabase._();

  static const String historyTable = 'browser_history';
  static const String downloadTable = 'browser_downloads';
  static const String favoriteTable = 'browser_favorites';
  static const int schemaVersion = 2;

  static final BrowserDatabase instance = BrowserDatabase._();

  Database? _database;

  Future<Database> get database async {
    final cachedDatabase = _database;
    if (cachedDatabase != null) {
      return cachedDatabase;
    }

    final databasePath = await getDatabasesPath();
    final path = p.join(databasePath, 'browser_data.db');
    final database = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _database = database;
    return database;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $historyTable (
        id INTEGER PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        visitedAt INTEGER NOT NULL,
        visitCount INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_browser_history_url ON $historyTable(url)',
    );
    await db.execute(
      'CREATE INDEX idx_browser_history_visited_at ON $historyTable(visitedAt DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_browser_history_visit_count ON $historyTable(visitCount DESC)',
    );

    await db.execute('''
      CREATE TABLE $downloadTable (
        id INTEGER PRIMARY KEY,
        url TEXT NOT NULL,
        fileName TEXT NOT NULL,
        status TEXT NOT NULL,
        savedPath TEXT,
        totalBytes INTEGER NOT NULL DEFAULT 0,
        bytesReceived INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_browser_downloads_created_at ON $downloadTable(createdAt DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_browser_downloads_status ON $downloadTable(status)',
    );

    await db.execute('''
      CREATE TABLE $favoriteTable (
        id INTEGER PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        sortOrder INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_browser_favorites_url ON $favoriteTable(url)',
    );
    await db.execute(
      'CREATE INDEX idx_browser_favorites_sort ON $favoriteTable(sortOrder ASC)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 1) {
      await _onCreate(db, newVersion);
    }
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE $favoriteTable (
          id INTEGER PRIMARY KEY,
          url TEXT NOT NULL,
          title TEXT NOT NULL,
          createdAt INTEGER NOT NULL,
          sortOrder INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX idx_browser_favorites_url ON $favoriteTable(url)',
      );
      await db.execute(
        'CREATE INDEX idx_browser_favorites_sort ON $favoriteTable(sortOrder ASC)',
      );
    }
  }

  Future<void> close() async {
    final database = _database;
    if (database == null) {
      return;
    }

    await database.close();
    _database = null;
  }
}
