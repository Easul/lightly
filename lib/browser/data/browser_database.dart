import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class BrowserDatabase {
  BrowserDatabase._();

  static const String historyTable = 'browser_history';
  static const String historyVisitsTable = 'browser_history_visits';
  static const String downloadTable = 'browser_downloads';
  static const String favoriteTable = 'browser_favorites';
  static const int schemaVersion = 3;

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
    await _createHistoryVisitsTable(db);

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
    if (oldVersion < 3) {
      await _createHistoryVisitsTable(db);
      await db.execute('''
        INSERT INTO $historyVisitsTable (url, title, visitedAt)
        SELECT url, title, visitedAt FROM $historyTable
      ''');
    }
  }

  static Future<void> _createHistoryVisitsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $historyVisitsTable (
        id INTEGER PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        visitedAt INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_browser_history_visits_time '
      'ON $historyVisitsTable(visitedAt DESC, id DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_browser_history_visits_url '
      'ON $historyVisitsTable(url)',
    );
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
