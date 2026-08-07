import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/ai/ai_response_sections.dart';

void main() {
  group('AiResponseSections', () {
    test('separates a completed think block from the answer', () {
      final sections = AiResponseSections.parse('<think>先分析问题</think>这是最终回答');

      expect(sections.reasoning, '先分析问题');
      expect(sections.answer, '这是最终回答');
      expect(sections.reasoningComplete, isTrue);
    });

    test('keeps an unclosed streaming think block in reasoning', () {
      final sections = AiResponseSections.parse('<thinking>正在分析');

      expect(sections.reasoning, '正在分析');
      expect(sections.answer, isEmpty);
      expect(sections.reasoningComplete, isFalse);
    });

    test('leaves a normal answer unchanged', () {
      final sections = AiResponseSections.parse('普通回答');

      expect(sections.reasoning, isEmpty);
      expect(sections.answer, '普通回答');
      expect(sections.reasoningComplete, isTrue);
    });

    test('combines repeated reasoning chunks from compatible APIs', () {
      final sections = AiResponseSections.parse(
        '<think>第一步</think><reasoning>，第二步</reasoning>结论',
      );

      expect(sections.reasoning, '第一步，第二步');
      expect(sections.answer, '结论');
    });
  });
}
