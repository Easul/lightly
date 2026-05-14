import 'package:flutter/material.dart';

enum SharedDownloadAccessChoice { requestPermission, useAppDirectory, cancel }

Future<SharedDownloadAccessChoice> showSharedDownloadAccessDialog(
  BuildContext context, {
  required String actionLabel,
}) async {
  final result = await showDialog<SharedDownloadAccessChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('需要文件访问授权'),
      content: Text(
        '若要把$actionLabel保存到系统 Download 目录，需要授予文件访问权限。'
        '如果暂时不授权，也可以继续保存到应用目录。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(SharedDownloadAccessChoice.cancel),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(SharedDownloadAccessChoice.useAppDirectory),
          child: const Text('保存到应用目录'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(SharedDownloadAccessChoice.requestPermission),
          child: const Text('去授权'),
        ),
      ],
    ),
  );
  return result ?? SharedDownloadAccessChoice.cancel;
}
