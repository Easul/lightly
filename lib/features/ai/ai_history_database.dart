import 'package:sqflite/sqflite.dart';

import '../../core/storage/app_database_provider.dart';

class AiChatSession {
  const AiChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AiChatSession.fromMap(Map<String, Object?> map) => AiChatSession(
    id: map['id'] as int,
    title: map['title'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
  );
}

class AiChatMessageRecord {
  const AiChatMessageRecord({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final int id;
  final int sessionId;
  final String role;
  final String content;
  final DateTime createdAt;

  factory AiChatMessageRecord.fromMap(Map<String, Object?> map) =>
      AiChatMessageRecord(
        id: map['id'] as int,
        sessionId: map['sessionId'] as int,
        role: map['role'] as String,
        content: map['content'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      );
}

class AiHistoryDatabase {
  AiHistoryDatabase({AppDatabaseProvider? database}) : _database = database;

  static final AiHistoryDatabase instance = AiHistoryDatabase();

  /// AI chat table names. These are a data contract — the strings must stay
  /// `ai_chat_sessions` / `ai_chat_messages` to match the existing schema.
  /// They previously lived on the shared database class; ownership moved here
  /// so AI does not depend on a concrete database. [AppDatabaseProvider]
  /// supplies the handle while `AppDatabase` executes the shared schema.
  static const String sessionTable = 'ai_chat_sessions';
  static const String messageTable = 'ai_chat_messages';

  /// Source of the shared database handle. Injected by the composition root so
  /// this feature does not depend on the concrete database. It
  /// has no safe empty default — unlike a proxy port, a missing database is a
  /// wiring error, not a degraded mode — so access before injection throws.
  AppDatabaseProvider? _database;

  set databaseProvider(AppDatabaseProvider provider) => _database = provider;

  Future<Database> get _db async {
    final provider = _database;
    if (provider == null) {
      throw StateError(
        'AiHistoryDatabase used before its AppDatabaseProvider was injected. '
        'Wire it in the composition root (AppServices) before AI history runs.',
      );
    }
    return provider.database;
  }

  Future<List<AiChatSession>> listSessions() async {
    final db = await _db;
    final rows = await db.query(sessionTable, orderBy: 'updatedAt DESC');
    return rows.map(AiChatSession.fromMap).toList(growable: false);
  }

  Future<AiChatSession> createSession(String title) async {
    final db = await _db;
    final now = DateTime.now();
    final id = await db.insert(sessionTable, <String, Object?>{
      'title': title.trim().isEmpty ? '新对话' : title.trim(),
      'createdAt': now.millisecondsSinceEpoch,
      'updatedAt': now.millisecondsSinceEpoch,
    });
    return AiChatSession(id: id, title: title, createdAt: now, updatedAt: now);
  }

  Future<void> renameSession(int id, String title) async {
    final db = await _db;
    await db.update(
      sessionTable,
      <String, Object?>{
        'title': title.trim(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteSession(int id) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await transaction.delete(
        messageTable,
        where: 'sessionId = ?',
        whereArgs: <Object?>[id],
      );
      await transaction.delete(
        sessionTable,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  Future<List<AiChatMessageRecord>> listMessages(int sessionId) async {
    final db = await _db;
    final rows = await db.query(
      messageTable,
      where: 'sessionId = ?',
      whereArgs: <Object?>[sessionId],
      orderBy: 'id ASC',
    );
    return rows.map(AiChatMessageRecord.fromMap).toList(growable: false);
  }

  Future<AiChatMessageRecord> addMessage({
    required int sessionId,
    required String role,
    required String content,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    final id = await db.transaction((transaction) async {
      final messageId = await transaction
          .insert(messageTable, <String, Object?>{
            'sessionId': sessionId,
            'role': role,
            'content': content,
            'createdAt': now.millisecondsSinceEpoch,
          });
      await transaction.update(
        sessionTable,
        <String, Object?>{'updatedAt': now.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: <Object?>[sessionId],
      );
      return messageId;
    });
    return AiChatMessageRecord(
      id: id,
      sessionId: sessionId,
      role: role,
      content: content,
      createdAt: now,
    );
  }

  Future<void> updateMessage(int id, String content) async {
    final db = await _db;
    await db.update(
      messageTable,
      <String, Object?>{'content': content},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteMessage(int id) async {
    final db = await _db;
    await db.delete(messageTable, where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
