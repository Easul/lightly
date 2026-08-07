class AiResponseSections {
  const AiResponseSections({
    required this.reasoning,
    required this.answer,
    required this.reasoningComplete,
  });

  final String reasoning;
  final String answer;
  final bool reasoningComplete;

  bool get hasReasoning => reasoning.isNotEmpty;

  static AiResponseSections parse(String source) {
    final reasoning = StringBuffer();
    final answer = StringBuffer();
    final tagPattern = RegExp(
      r'</?(?:think|thinking|reasoning)>',
      caseSensitive: false,
    );
    var offset = 0;
    var inReasoning = false;
    var foundReasoningTag = false;

    for (final match in tagPattern.allMatches(source)) {
      final segment = source.substring(offset, match.start);
      (inReasoning ? reasoning : answer).write(segment);

      final tag = match.group(0)!;
      if (tag.startsWith('</')) {
        if (inReasoning) inReasoning = false;
      } else {
        foundReasoningTag = true;
        inReasoning = true;
      }
      offset = match.end;
    }

    final remaining = source.substring(offset);
    (inReasoning ? reasoning : answer).write(remaining);

    if (!foundReasoningTag) {
      return AiResponseSections(
        reasoning: '',
        answer: source.trim(),
        reasoningComplete: true,
      );
    }
    return AiResponseSections(
      reasoning: reasoning.toString().trim(),
      answer: answer.toString().trim(),
      reasoningComplete: !inReasoning,
    );
  }
}
