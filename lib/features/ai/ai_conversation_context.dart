import 'ai_client.dart';

class AiConversationContextResult {
  const AiConversationContextResult({
    required this.messages,
    required this.omittedMessageCount,
  });

  final List<AiMessage> messages;
  final int omittedMessageCount;
}

class AiConversationContext {
  const AiConversationContext._();

  static const int defaultMaxCharacters = 48000;
  static const int defaultMaxMessages = 50;

  static AiConversationContextResult build(
    Iterable<AiMessage> messages, {
    int maxCharacters = defaultMaxCharacters,
    int maxMessages = defaultMaxMessages,
  }) {
    final source = messages.toList(growable: false);
    final systemMessages = source
        .where((message) => message.role == 'system')
        .toList(growable: false);
    final conversation = source
        .where((message) => message.role != 'system')
        .toList(growable: false);
    final selected = <AiMessage>[];
    var usedCharacters = systemMessages.fold<int>(
      0,
      (total, message) => total + message.content.length,
    );

    for (var index = conversation.length - 1; index >= 0; index--) {
      final message = conversation[index];
      final wouldExceedCharacters =
          usedCharacters + message.content.length > maxCharacters;
      final wouldExceedMessages = selected.length >= maxMessages;
      if (selected.isNotEmpty &&
          (wouldExceedCharacters || wouldExceedMessages)) {
        break;
      }
      selected.add(message);
      usedCharacters += message.content.length;
    }

    final retainedConversation = selected.reversed.toList(growable: false);
    return AiConversationContextResult(
      messages: <AiMessage>[...systemMessages, ...retainedConversation],
      omittedMessageCount: conversation.length - retainedConversation.length,
    );
  }
}
