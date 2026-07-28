import 'dart:convert';

import 'telegram_checkin_models.dart';

typedef TelegramJson = Map<String, dynamic>;

class TelegramTdJsonCodec {
  const TelegramTdJsonCodec();

  String encodeRequest(
    String type, {
    Map<String, Object?> arguments = const <String, Object?>{},
    required String extra,
  }) {
    return jsonEncode(<String, Object?>{
      '@type': type,
      ...arguments,
      '@extra': extra,
    });
  }

  TelegramJson decodeObject(String raw) {
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  bool isError(TelegramJson value) => value['@type'] == 'error';

  int errorCode(TelegramJson value) => (value['code'] as num?)?.toInt() ?? 0;

  String errorMessage(TelegramJson value) {
    return value['message'] as String? ?? '未知 Telegram 错误';
  }

  TelegramChatSummary chatSummary(TelegramJson chat) {
    final lastMessage = mapOrNull(chat['last_message']);
    return TelegramChatSummary(
      id: (chat['id'] as num).toInt(),
      title: chat['title'] as String? ?? '',
      lastMessage: lastMessage == null
          ? ''
          : messageText(mapOrEmpty(lastMessage['content'])),
      date: lastMessage == null ? null : _dateFromSeconds(lastMessage['date']),
      unreadCount: (chat['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  TelegramMessagePreview messagePreview(TelegramJson message) {
    return TelegramMessagePreview(
      id: (message['id'] as num).toInt(),
      text: messageText(mapOrEmpty(message['content'])),
      date:
          _dateFromSeconds(message['date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isOutgoing: message['is_outgoing'] == true,
    );
  }

  String messageText(TelegramJson content) {
    final type = content['@type'] as String? ?? 'unsupported';
    if (type == 'messageText') {
      return mapOrEmpty(content['text'])['text'] as String? ?? '';
    }
    return '[$type]';
  }

  TelegramJson mapOrEmpty(Object? value) {
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  TelegramJson? mapOrNull(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  List<TelegramJson> mapList(Object? value) {
    return (value as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  DateTime? _dateFromSeconds(Object? value) {
    final seconds = (value as num?)?.toInt();
    return seconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
}
