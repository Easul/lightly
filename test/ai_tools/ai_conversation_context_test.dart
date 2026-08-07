import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/ai/ai_client.dart';
import 'package:lightly/features/ai/ai_conversation_context.dart';

void main() {
  test('keeps system and newest conversation messages within limits', () {
    final result = AiConversationContext.build(
      const <AiMessage>[
        AiMessage(role: 'system', content: 'system'),
        AiMessage(role: 'user', content: 'old user'),
        AiMessage(role: 'assistant', content: 'old assistant'),
        AiMessage(role: 'user', content: 'latest user'),
      ],
      maxCharacters: 24,
      maxMessages: 2,
    );

    expect(result.messages.first.role, 'system');
    expect(result.messages.last.content, 'latest user');
    expect(result.omittedMessageCount, 2);
  });

  test('always keeps the newest oversized message', () {
    final result = AiConversationContext.build(const <AiMessage>[
      AiMessage(role: 'user', content: 'older'),
      AiMessage(role: 'user', content: 'a very long latest message'),
    ], maxCharacters: 4);

    expect(result.messages, hasLength(1));
    expect(result.messages.single.content, 'a very long latest message');
    expect(result.omittedMessageCount, 1);
  });
}
