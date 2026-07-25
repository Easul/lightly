import 'package:flutter/material.dart';

class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks
          .map((block) => _MarkdownBlockView(block: block))
          .toList(growable: false),
    );
  }

  List<_MarkdownBlock> _parseBlocks(String source) {
    final blocks = <_MarkdownBlock>[];
    final paragraph = <String>[];
    final code = <String>[];
    var inCode = false;

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(_MarkdownBlock(_BlockType.paragraph, paragraph.join('\n')));
      paragraph.clear();
    }

    for (final line in source.split('\n')) {
      if (line.trimLeft().startsWith('```')) {
        if (inCode) {
          blocks.add(_MarkdownBlock(_BlockType.code, code.join('\n')));
          code.clear();
        } else {
          flushParagraph();
        }
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        code.add(line);
        continue;
      }
      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }
      if (line.startsWith('#')) {
        flushParagraph();
        final level =
            line.length - line.replaceFirst(RegExp(r'^#+'), '').length;
        blocks.add(
          _MarkdownBlock(
            _BlockType.heading,
            line.substring(level).trim(),
            level: level,
          ),
        );
        continue;
      }
      if (RegExp(r'^\s*[-*+]\s+').hasMatch(line)) {
        flushParagraph();
        blocks.add(
          _MarkdownBlock(
            _BlockType.listItem,
            line.replaceFirst(RegExp(r'^\s*[-*+]\s+'), ''),
          ),
        );
        continue;
      }
      paragraph.add(line);
    }
    if (code.isNotEmpty) {
      blocks.add(_MarkdownBlock(_BlockType.code, code.join('\n')));
    }
    flushParagraph();
    return blocks;
  }
}

enum _BlockType { paragraph, heading, listItem, code }

class _MarkdownBlock {
  const _MarkdownBlock(this.type, this.text, {this.level = 1});

  final _BlockType type;
  final String text;
  final int level;
}

class _MarkdownBlockView extends StatelessWidget {
  const _MarkdownBlockView({required this.block});

  final _MarkdownBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (block.type == _BlockType.code) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SelectableText(
          block.text,
          style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        ),
      );
    }
    final style = block.type == _BlockType.heading
        ? switch (block.level) {
            1 => theme.textTheme.titleLarge,
            2 => theme.textTheme.titleMedium,
            _ => theme.textTheme.titleSmall,
          }
        : theme.textTheme.bodyMedium?.copyWith(height: 1.45);
    final content = SelectableText.rich(
      TextSpan(style: style, children: _inlineSpans(context, block.text)),
    );
    if (block.type == _BlockType.listItem) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2, right: 7),
              child: Text('•'),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: content);
  }

  List<InlineSpan> _inlineSpans(BuildContext context, String text) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*)');
    var offset = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: TextStyle(
              fontFamily: 'monospace',
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
        );
      } else if (token.startsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      offset = match.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return spans;
  }
}
