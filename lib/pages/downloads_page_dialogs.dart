import 'package:flutter/material.dart';

enum DownloadDeleteChoice { recordOnly, recordAndFile }

class ManualDownloadRequest {
  const ManualDownloadRequest({required this.url, required this.fileName});

  final String url;
  final String fileName;
}

Future<DownloadDeleteChoice?> showDownloadDeleteDialog(
  BuildContext context, {
  required String fileName,
}) {
  return showDialog<DownloadDeleteChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('删除下载'),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('仅删除记录'),
            subtitle: const Text('保留设备中的文件'),
            onTap: () => Navigator.of(
              dialogContext,
            ).pop(DownloadDeleteChoice.recordOnly),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(dialogContext).colorScheme.error,
            ),
            title: Text(
              '删除记录和文件',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
              ),
            ),
            subtitle: const Text('同时删除设备中的文件'),
            onTap: () => Navigator.of(
              dialogContext,
            ).pop(DownloadDeleteChoice.recordAndFile),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

Future<ManualDownloadRequest?> showManualDownloadDialog(
  BuildContext context,
) async {
  final urlController = TextEditingController();
  final fileNameController = TextEditingController();
  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('下载文件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: '文件链接',
                hintText: 'https://example.com/file.zip',
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
              onChanged: (value) {
                final uri = Uri.tryParse(value.trim());
                if (uri != null && uri.pathSegments.isNotEmpty) {
                  final segment = uri.pathSegments.last;
                  if (segment.isNotEmpty && fileNameController.text.isEmpty) {
                    fileNameController.text = segment;
                  }
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: fileNameController,
              decoration: const InputDecoration(
                labelText: '文件名',
                hintText: 'file.zip',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('下载'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return null;
    }

    return ManualDownloadRequest(
      url: urlController.text.trim(),
      fileName: fileNameController.text.trim(),
    );
  } finally {
    urlController.dispose();
    fileNameController.dispose();
  }
}
