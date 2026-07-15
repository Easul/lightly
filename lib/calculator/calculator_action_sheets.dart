import 'package:flutter/material.dart';

import 'calculation_history.dart';

Future<void> showCalculationNoteDialog({
  required BuildContext context,
  required CalculationHistory entry,
  required Future<void> Function(String id, String note) onSaveNote,
}) async {
  final noteController = TextEditingController(text: entry.note);
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑备注'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            labelText: '备注',
            hintText: '输入备注信息',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final note = noteController.text;
              Navigator.of(context).pop();
              await onSaveNote(entry.id, note);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  } finally {
    noteController.dispose();
  }
}

Future<void> showCalculationCopyMenu({
  required BuildContext context,
  required CalculationHistory entry,
  required ValueChanged<String> onCopy,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('复制表达式'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              onCopy(entry.expression);
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            title: const Text('复制结果'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              onCopy(entry.result);
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            title: const Text('复制完整表达式'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              onCopy('${entry.expression} = ${entry.result}');
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    ),
  );
}
