import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/telegram/telegram_td_json_codec.dart';

void main() {
  const codec = TelegramTdJsonCodec();

  test('encodes TDLib requests with stable extra and UTF-8 content', () {
    final raw = codec.encodeRequest(
      'sendMessage',
      arguments: <String, Object?>{'chat_id': 42, 'text': '中文🙂'},
      extra: 'tg_7',
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;

    expect(decoded['@type'], 'sendMessage');
    expect(decoded['@extra'], 'tg_7');
    expect(decoded['text'], '中文🙂');
  });

  test('parses chat summaries and Telegram text messages', () {
    final chat = codec.chatSummary(<String, dynamic>{
      '@type': 'chat',
      'id': 123,
      'title': '测试会话',
      'unread_count': 2,
      'last_message': <String, dynamic>{
        'id': 9,
        'date': 1700000000,
        'is_outgoing': false,
        'content': <String, dynamic>{
          '@type': 'messageText',
          'text': <String, dynamic>{'text': 'hello'},
        },
      },
    });

    expect(chat.id, 123);
    expect(chat.title, '测试会话');
    expect(chat.lastMessage, 'hello');
    expect(chat.unreadCount, 2);
    expect(chat.date, isNotNull);
  });

  test('preserves non-text message constructor labels and errors', () {
    expect(
      codec.messageText(<String, dynamic>{'@type': 'messagePhoto'}),
      '[messagePhoto]',
    );
    final error = codec.decodeObject(
      '{"@type":"error","code":401,"message":"unauthorized"}',
    );
    expect(codec.isError(error), isTrue);
    expect(codec.errorCode(error), 401);
    expect(codec.errorMessage(error), 'unauthorized');
  });
}
