import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown(this.data, {super.key, this.onLinkTap});

  final String data;
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks
          .map(
            (block) => _MarkdownBlockView(block: block, onLinkTap: onLinkTap),
          )
          .toList(growable: false),
    );
  }

  List<_MarkdownBlock> _parseBlocks(String source) {
    final blocks = <_MarkdownBlock>[];
    final paragraph = <String>[];
    final code = <String>[];
    final lines = source.split('\n');
    var inCode = false;
    var codeLanguage = '';

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(_MarkdownBlock.paragraph(paragraph.join('\n')));
      paragraph.clear();
    }

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final trimmedLeft = line.trimLeft();
      if (trimmedLeft.startsWith('```')) {
        if (inCode) {
          blocks.add(
            _MarkdownBlock.code(code.join('\n'), language: codeLanguage),
          );
          code.clear();
          codeLanguage = '';
        } else {
          flushParagraph();
          codeLanguage = trimmedLeft.substring(3).trim();
        }
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        code.add(line);
        continue;
      }
      if (_isTableHeader(lines, index)) {
        flushParagraph();
        final rows = <List<String>>[_splitTableRow(line)];
        index += 2;
        while (index < lines.length &&
            lines[index].trim().isNotEmpty &&
            lines[index].contains('|')) {
          rows.add(_splitTableRow(lines[index]));
          index++;
        }
        index--;
        blocks.add(_MarkdownBlock.table(rows));
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
          _MarkdownBlock.heading(line.substring(level).trim(), level: level),
        );
        continue;
      }
      final orderedMatch = RegExp(r'^\s*(\d+)\.\s+(.+)$').firstMatch(line);
      if (orderedMatch != null) {
        flushParagraph();
        blocks.add(
          _MarkdownBlock.listItem(
            orderedMatch.group(2)!,
            marker: '${orderedMatch.group(1)}.',
          ),
        );
        continue;
      }
      if (RegExp(r'^\s*[-*+]\s+').hasMatch(line)) {
        flushParagraph();
        blocks.add(
          _MarkdownBlock.listItem(
            line.replaceFirst(RegExp(r'^\s*[-*+]\s+'), ''),
          ),
        );
        continue;
      }
      if (trimmedLeft.startsWith('> ')) {
        flushParagraph();
        blocks.add(_MarkdownBlock.quote(trimmedLeft.substring(2)));
        continue;
      }
      paragraph.add(line);
    }
    if (code.isNotEmpty) {
      blocks.add(_MarkdownBlock.code(code.join('\n'), language: codeLanguage));
    }
    flushParagraph();
    return blocks;
  }

  bool _isTableHeader(List<String> lines, int index) {
    if (index + 1 >= lines.length || !lines[index].contains('|')) return false;
    final separator = _splitTableRow(lines[index + 1]);
    return separator.isNotEmpty &&
        separator.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell));
  }

  List<String> _splitTableRow(String line) {
    var normalized = line.trim();
    if (normalized.startsWith('|')) normalized = normalized.substring(1);
    if (normalized.endsWith('|')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.split('|').map((cell) => cell.trim()).toList();
  }
}

enum _BlockType { paragraph, heading, listItem, code, quote, table }

class _MarkdownBlock {
  const _MarkdownBlock._(
    this.type,
    this.text, {
    this.level = 1,
    this.marker = '•',
    this.language = '',
    this.tableRows = const <List<String>>[],
  });

  factory _MarkdownBlock.paragraph(String text) =>
      _MarkdownBlock._(_BlockType.paragraph, text);

  factory _MarkdownBlock.heading(String text, {required int level}) =>
      _MarkdownBlock._(_BlockType.heading, text, level: level);

  factory _MarkdownBlock.listItem(String text, {String marker = '•'}) =>
      _MarkdownBlock._(_BlockType.listItem, text, marker: marker);

  factory _MarkdownBlock.code(String text, {String language = ''}) =>
      _MarkdownBlock._(_BlockType.code, text, language: language);

  factory _MarkdownBlock.quote(String text) =>
      _MarkdownBlock._(_BlockType.quote, text);

  factory _MarkdownBlock.table(List<List<String>> rows) =>
      _MarkdownBlock._(_BlockType.table, '', tableRows: rows);

  final _BlockType type;
  final String text;
  final int level;
  final String marker;
  final String language;
  final List<List<String>> tableRows;
}

class _MarkdownBlockView extends StatelessWidget {
  const _MarkdownBlockView({required this.block, required this.onLinkTap});

  final _MarkdownBlock block;
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (block.type == _BlockType.code) return _buildCodeBlock(context);
    if (block.type == _BlockType.table) return _buildTable(context);

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
            SizedBox(
              width: block.marker == '•' ? 18 : 28,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(block.marker),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    if (block.type == _BlockType.quote) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
          ),
        ),
        child: content,
      );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: content);
  }

  Widget _buildCodeBlock(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 3, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    block.language.isEmpty ? '代码' : block.language,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                IconButton(
                  tooltip: '复制代码',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    unawaited(
                      Clipboard.setData(ClipboardData(text: block.text)),
                    );
                    ScaffoldMessenger.maybeOf(
                      context,
                    )?.showSnackBar(const SnackBar(content: Text('代码已复制')));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 17),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SelectableText(
              block.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final rows = block.tableRows;
    if (rows.isEmpty) return const SizedBox.shrink();
    final columnCount = rows.first.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 60,
        columnSpacing: 20,
        columns: List<DataColumn>.generate(
          columnCount,
          (index) => DataColumn(
            label: Text(rows.first[index], overflow: TextOverflow.ellipsis),
          ),
        ),
        rows: rows
            .skip(1)
            .map(
              (row) => DataRow(
                cells: List<DataCell>.generate(
                  columnCount,
                  (index) => DataCell(
                    SelectableText(index < row.length ? row[index] : ''),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  List<InlineSpan> _inlineSpans(BuildContext context, String text) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(\[[^\]]+\]\(https?://[^\s)]+\)|`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*)',
    );
    var offset = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      final token = match.group(0)!;
      final linkMatch = RegExp(
        r'^\[([^\]]+)\]\((https?://[^\s)]+)\)$',
      ).firstMatch(token);
      if (linkMatch != null) {
        final label = linkMatch.group(1)!;
        final url = linkMatch.group(2)!;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: onLinkTap == null ? null : () => onLinkTap!(url),
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        );
      } else if (token.startsWith('`')) {
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
