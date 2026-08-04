import 'package:flutter/material.dart';

import '../application/music_player_controller.dart';
import '../domain/music_library_sort.dart';
import '../infrastructure/music_settings_store.dart';

/// Asks whether playback should resume from the remembered position. Returns
/// `true` to resume, `false` to start over, and `null` when dismissed.
Future<bool?> showMusicResumePromptDialog(
  BuildContext context,
  MusicResumeRequest request,
) {
  final totalSeconds = request.position.inSeconds;
  final label =
      '${totalSeconds ~/ 60}:${(totalSeconds % 60).toString().padLeft(2, '0')}';
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('继续上次播放？'),
      content: Text('“${request.track.title}”上次播放到 $label。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('从头播放'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('继续播放'),
        ),
      ],
    ),
  );
}

Future<MusicSettings?> showMusicSettingsDialog(
  BuildContext context,
  MusicSettings initial,
) {
  final apiBaseUrlController = TextEditingController(text: initial.apiBaseUrl);
  final apiKeyController = TextEditingController(text: initial.apiKey);
  var quality = initial.quality;
  var notificationEnabled = initial.notificationEnabled;
  var resumePromptEnabled = initial.resumePromptEnabled;
  var obscureApiKey = true;
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
                obscureText: obscureApiKey,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: obscureApiKey ? '显示 API Key' : '隐藏 API Key',
                    onPressed: () {
                      setDialogState(() => obscureApiKey = !obscureApiKey);
                    },
                    icon: Icon(
                      obscureApiKey
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  ),
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('记住播放进度'),
                subtitle: const Text('再次播放时询问是否从上次位置继续'),
                value: resumePromptEnabled,
                onChanged: (value) {
                  setDialogState(() => resumePromptEnabled = value);
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
                resumePromptEnabled: resumePromptEnabled,
                librarySort: initial.librarySort,
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

Future<MusicLibrarySort?> showMusicSortDialog(
  BuildContext context,
  MusicLibrarySort current,
) {
  return showModalBottomSheet<MusicLibrarySort>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '排序方式',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          ...MusicLibrarySort.options.map(
            (option) => ListTile(
              leading: Icon(
                option == current
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: option == current
                    ? Theme.of(sheetContext).colorScheme.primary
                    : null,
              ),
              title: Text(option.label),
              onTap: () => Navigator.pop(sheetContext, option),
            ),
          ),
        ],
      ),
    ),
  );
}
