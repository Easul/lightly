import 'package:flutter/material.dart';

class ManualDownloadRequest {
  const ManualDownloadRequest({required this.url, required this.fileName});

  final String url;
  final String fileName;
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
