import 'package:flutter/material.dart';

import '../infrastructure/music_settings_store.dart';

Future<MusicSettings?> showMusicSettingsDialog(
  BuildContext context,
  MusicSettings initial,
) {
  final apiBaseUrlController = TextEditingController(text: initial.apiBaseUrl);
  final apiKeyController = TextEditingController(text: initial.apiKey);
  var quality = initial.quality;
  var notificationEnabled = initial.notificationEnabled;
  return showDialog<MusicSettings>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('音乐设置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: apiBaseUrlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'API 地址',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: apiKeyController,
                obscureText: true,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: quality,
                decoration: const InputDecoration(
                  labelText: '音质',
                  prefixIcon: Icon(Icons.graphic_eq_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'standard', child: Text('标准')),
                  DropdownMenuItem(value: 'exhigh', child: Text('极高')),
                  DropdownMenuItem(value: 'lossless', child: Text('无损')),
                  DropdownMenuItem(value: 'hires', child: Text('Hi-Res')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => quality = value);
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('系统播放工具栏'),
                subtitle: const Text('锁屏和通知栏'),
                value: notificationEnabled,
                onChanged: (value) {
                  setDialogState(() => notificationEnabled = value);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              MusicSettings(
                apiBaseUrl: apiBaseUrlController.text.trim(),
                apiKey: apiKeyController.text.trim(),
                quality: quality,
                notificationEnabled: notificationEnabled,
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  ).whenComplete(() {
    apiBaseUrlController.dispose();
    apiKeyController.dispose();
  });
}

Future<String?> showMusicGroupDialog(
  BuildContext context, {
  required String currentGroup,
  required List<String> existingGroups,
}) {
  final controller = TextEditingController(text: currentGroup);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('歌曲分组'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '分组名称',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
          ),
          if (existingGroups.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: existingGroups
                  .map(
                    (group) => ActionChip(
                      label: Text(group),
                      onPressed: () => controller.text = group,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
      actions: [
        if (currentGroup.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('移出分组'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
