import '../browser/data/browser_database.dart';

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
  AiHistoryDatabase({BrowserDatabase? database})
    : _database = database ?? BrowserDatabase.instance;

  static final AiHistoryDatabase instance = AiHistoryDatabase();

  final BrowserDatabase _database;

  Future<List<AiChatSession>> listSessions() async {
    final db = await _database.database;
    final rows = await db.query(
      BrowserDatabase.aiChatSessionTable,
      orderBy: 'updatedAt DESC',
    );
    return rows.map(AiChatSession.fromMap).toList(growable: false);
  }

  Future<AiChatSession> createSession(String title) async {
    final db = await _database.database;
    final now = DateTime.now();
    final id = await db
        .insert(BrowserDatabase.aiChatSessionTable, <String, Object?>{
          'title': title.trim().isEmpty ? '新对话' : title.trim(),
          'createdAt': now.millisecondsSinceEpoch,
          'updatedAt': now.millisecondsSinceEpoch,
        });
    return AiChatSession(id: id, title: title, createdAt: now, updatedAt: now);
  }

  Future<void> renameSession(int id, String title) async {
    final db = await _database.database;
    await db.update(
      BrowserDatabase.aiChatSessionTable,
      <String, Object?>{
        'title': title.trim(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteSession(int id) async {
    final db = await _database.database;
    await db.transaction((transaction) async {
      await transaction.delete(
        BrowserDatabase.aiChatMessageTable,
        where: 'sessionId = ?',
        whereArgs: <Object?>[id],
      );
      await transaction.delete(
        BrowserDatabase.aiChatSessionTable,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  Future<List<AiChatMessageRecord>> listMessages(int sessionId) async {
    final db = await _database.database;
    final rows = await db.query(
      BrowserDatabase.aiChatMessageTable,
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
    final db = await _database.database;
    final now = DateTime.now();
    final id = await db.transaction((transaction) async {
      final messageId = await transaction
          .insert(BrowserDatabase.aiChatMessageTable, <String, Object?>{
            'sessionId': sessionId,
            'role': role,
            'content': content,
            'createdAt': now.millisecondsSinceEpoch,
          });
      await transaction.update(
        BrowserDatabase.aiChatSessionTable,
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
    final db = await _database.database;
    await db.update(
      BrowserDatabase.aiChatMessageTable,
      <String, Object?>{'content': content},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteMessage(int id) async {
    final db = await _database.database;
    await db.delete(
      BrowserDatabase.aiChatMessageTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
